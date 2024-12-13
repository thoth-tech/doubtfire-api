require 'aws-sdk-ses' # v2: require 'aws-sdk'

def use_ses_for_mail(sender, recipient, subject, htmlbody, textbody, encoding){
    ses = Aws::SES::Client.new(region: '')
    begin
        ses.send_email(
            destination: {to_addresses: [recipient]}, message: {
                body: {
                    html: {
                    charset: encoding,
                    data: htmlbody
                    },
                    text: {
                    charset: encoding,
                    data: textbody
                    }
                },
                subject: {
                    charset: encoding,
                    data: subject
                }
            }, source: sender
        )

    puts "Email sent to #{recipient}"
    rescue Aws::SES::Errors::ServiceError => e
        puts "Email not sent. Error message: #{e}"
    end
}