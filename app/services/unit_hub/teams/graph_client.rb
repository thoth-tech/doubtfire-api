# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'timeout'

module UnitHub
  module Teams
    class GraphClient
      class Error < StandardError; end
      class AccessDenied < Error; end
      class MissingMessage < Error; end

      class Throttled < Error
        attr_reader :retry_after

        def initialize(retry_after)
          @retry_after = retry_after.to_i.clamp(60, 86_400)
          super('Teams is throttling requests.')
        end
      end
      MAX_RESPONSE_BYTES = 2.megabytes
      MAX_PAGES = 2
      MESSAGE_ID = /\A[A-Za-z0-9_-]{1,128}\z/

      attr_reader :tenant_id

      def initialize(credentials, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 180)
        @credentials = credentials
        @tenant_id = credentials.fetch(:tenant_id)
        unless @tenant_id.match?(Configuration::GUID) && credentials.fetch(:client_id).match?(Configuration::GUID)
          raise Error, 'Teams application identifiers are invalid.'
        end
        @deadline = deadline
      end

      def messages(mapping)
        path = channel_path(mapping)
        url = "https://graph.microsoft.com#{path}?$top=50"
        visited = []
        result = []
        MAX_PAGES.times do
          raise Error, 'Teams pagination repeated a page.' if visited.include?(url)

          visited << url
          response = get_json(url, path: path)
          values = response['value']
          raise Error, 'Teams returned an invalid message collection.' unless values.is_a?(Array) && values.length <= 50

          result.concat(values)
          url = response['@odata.nextLink']
          break if url.blank?

          validate_graph_url!(url, path)
        end
        result
      end

      def message(mapping, id)
        raise Error, 'Teams message ID is invalid.' unless id.to_s.match?(MESSAGE_ID)

        path = "#{channel_path(mapping)}/#{id}"
        get_json("https://graph.microsoft.com#{path}", path: path)
      end

      private

      def channel_path(mapping)
        "/v1.0/teams/#{mapping.team_id}/channels/#{ERB::Util.url_encode(mapping.channel_id)}/messages"
      end

      def validate_graph_url!(value, expected_path)
        uri = URI.parse(value.to_s)
        unless value.is_a?(String) && value.bytesize <= 8192 && !value.match?(/[[:space:][:cntrl:]]/) &&
               uri.is_a?(URI::HTTPS) && uri.host == 'graph.microsoft.com' && uri.port == 443 &&
               uri.userinfo.nil? && uri.fragment.nil? &&
               URI::DEFAULT_PARSER.unescape(uri.path) == URI::DEFAULT_PARSER.unescape(expected_path)
          raise Error, 'Teams pagination URL is outside the configured channel.'
        end
        uri
      rescue URI::InvalidURIError
        raise Error, 'Teams pagination URL is invalid.'
      end

      def token
        return @token if @token

        uri = URI("https://login.microsoftonline.com/#{@tenant_id}/oauth2/v2.0/token")
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(client_id: @credentials.fetch(:client_id), client_secret: @credentials.fetch(:client_secret),
                              grant_type: 'client_credentials', scope: 'https://graph.microsoft.com/.default')
        response = request_json(uri, request, token_request: true)
        access_token = response['access_token']
        unless response['token_type'].to_s.casecmp('Bearer').zero? && access_token.is_a?(String) &&
               access_token.bytesize.between?(1, 32_768) && !access_token.match?(/[[:space:][:cntrl:]]/)
          raise Error, 'Teams token response was invalid.'
        end
        @token = access_token
      end

      def get_json(url, path:)
        uri = validate_graph_url!(url, path)
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{token}"
        request['Accept'] = 'application/json'
        request_json(uri, request)
      end

      def request_json(uri, request, token_request: false)
        raise Error, 'Teams sync time limit reached.' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline

        body = +''
        code = nil
        retry_after = 300
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10, write_timeout: 5) do |http|
          http.max_retries = 0
          http.request(request) do |response|
            code = response.code.to_i
            retry_after = response['Retry-After'].to_i if response['Retry-After'].to_s.match?(/\A\d+\z/)
            response.read_body do |chunk|
              raise Error, 'Teams sync time limit reached.' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline
              raise Error, 'Teams response exceeded the size limit.' if body.bytesize + chunk.bytesize > MAX_RESPONSE_BYTES

              body << chunk
            end
          end
        end
        raise Throttled, retry_after if code == 429
        raise AccessDenied, 'Teams access was denied.' if [401, 403].include?(code) || (token_request && code == 400)
        raise MissingMessage, 'Teams message is unavailable.' if [404, 410].include?(code)
        raise Error, "Teams request failed (HTTP #{code})." unless code == 200

        value = JSON.parse(body)
        raise Error, 'Teams returned an invalid response.' unless value.is_a?(Hash)

        value
      rescue JSON::ParserError
        raise Error, 'Teams returned invalid JSON.'
      rescue IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
        # Never propagate provider bodies, URLs, request headers or credentials.
        raise Error, 'Teams could not be reached securely.'
      end
    end
  end
end
