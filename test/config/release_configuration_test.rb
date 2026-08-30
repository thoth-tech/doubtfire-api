# frozen_string_literal: true

require 'test_helper'

class ReleaseConfigurationTest < Minitest::Test
  RUBY_BASE = 'ruby:3.4.10-bookworm@sha256:56e0c9fdbf64d090e45072d32f0d3be7f2e392e733444f7d176a50881e6c325a'

  def test_production_application_images_are_pinned_and_daemon_free
    api = read('deployApi.Dockerfile')
    worker = read('deployAppSvr.Dockerfile')

    assert_match(/^FROM #{Regexp.escape(RUBY_BASE)}$/m, api)
    assert_match(/^FROM #{Regexp.escape(RUBY_BASE)}$/m, worker)
    assert_includes read('Gemfile.lock'), 'ruby 3.4.10p104'
    assert_match(
      /^FROM docker:28\.5\.2-cli@sha256:[0-9a-f]{64} AS docker_cli$/m,
      worker
    )

    [api, worker].each do |dockerfile|
      assert_equal false, /\b(?:docker-ce|containerd\.io)\b/.match?(dockerfile)
      assert_equal false, /^\s*redis\s*\\?$/m.match?(dockerfile)
      assert_match(/bundle config set deployment true/, dockerfile)
    end

    assert_equal false, /db:migrate/.match?(api)
    assert_match(
      /CMD \["bundle", "exec", "rails", "server", "-b", "0\.0\.0\.0"\]/,
      api
    )
  end

  def test_docker_build_context_excludes_local_credentials
    dockerignore = read('.dockerignore').lines.map(&:strip)
    required_patterns = %w[
      .docker
      .bundle
      .env
      .env.*
      .npmrc
      .gem/credentials
      .ssh
      .aws
      .config/gcloud
      config/master.key
      config/credentials
      config/credentials.yml.enc
      **/*.key
      **/*.pem
      **/*.p12
      **/*.pfx
      **/*.jks
      **/*.keystore
    ]

    required_patterns.each { |pattern| assert_includes dockerignore, pattern }
    assert_includes dockerignore, '!.env.example'
  end

  def test_helper_images_pin_bases_and_verify_downloads
    texlive = read('texlive.Dockerfile')
    jplag = read('jplag.Dockerfile')

    texlive.scan(/^FROM (\S+)/).flatten.each do |base|
      assert_match(/@sha256:[0-9a-f]{64}\z/, base)
    end
    assert_includes texlive, '/historic/systems/texlive/2025/tlnet-final'
    assert_includes texlive, 'sha512sum --check'
    assert_includes texlive, 'tlmgr --repository "$TL_MIRROR" install'
    assert_includes texlive, 'pdfmanagement-testphase'
    assert_equal false, /^\s*pdfmanagement\s*\\$/m.match?(texlive)
    assert_includes texlive, 'kpsewhich pdfmanagement-testphase.sty'
    assert_includes texlive, '--jobname=pdfmanagement-smoke'

    assert_match(/^FROM alpine:3\.23\.3@sha256:[0-9a-f]{64}$/m, jplag)
    assert_includes jplag, 'JPLAG_SHA256='
    assert_includes jplag, 'sha256sum -c -'
  end

  def test_release_lock_stays_above_known_security_floors
    minimum_versions = {
      'concurrent-ruby' => '1.3.7', # GHSA-h8w8-99g7-qmvj
      'crass' => '1.0.7',           # GHSA-6wmf-3r64-vcwv
      'net-imap' => '0.5.14',       # GHSA-vcgp-9326-pqcp
      'nokogiri' => '1.19.3',       # GHSA-c4rq-3m3g-8wgx and GHSA-353f-x4gh-cqq8
      'uri' => '1.0.4',             # GHSA-j4pr-3wm6-xx2r
      'websocket-driver' => '0.8.2', # GHSA-2x63-gw47-w4mm
      'yard' => '0.9.42' # CVE-2026-41493 (development/test)
    }

    minimum_versions.each do |name, minimum|
      versions = locked_versions(name)
      assert_operator versions.length, :>, 0, "#{name} must remain in Gemfile.lock"
      versions.each do |version|
        assert_operator version, :>=, Gem::Version.new(minimum), "#{name} #{version} is below #{minimum}"
      end
    end
  end

  def test_test_database_schema_fingerprint_stays_stable
    schema = read('db/schema.rb')
    migration = read('db/migrate/20260824000002_ensure_target_grade_changed_at_default.rb')
    workflow = read('.github/workflows/push.yml')
    database_preparation = read('script/prepare_test_database.sh')

    assert_includes schema, 'default: -> { "current_timestamp(6)" }'
    assert_includes migration, "-> { 'CURRENT_TIMESTAMP(6)' }"
    assert_includes workflow, 'run: script/prepare_test_database.sh'
    assert_includes workflow, 'git diff --exit-code -- db/schema.rb'
    assert_includes database_preparation, "abort 'db:populate created no units' unless Unit.exists?"
  end

  def test_development_compose_has_no_literal_institution_credential
    compose = read('docker-compose.yml')

    assert_match(/DF_SECRET_KEY_AAF:\s*\$\{DF_SECRET_KEY_AAF:-\}/, compose)
    assert_equal false, %r{https?://[^\s$]*(?:aaf\.edu\.au|deakin\.edu\.au)}i.match?(compose)
  end

  def test_production_image_workflow_actions_are_immutable
    all_workflows = Rails.root.join('.github/workflows').children
    all_workflows.select! { |path| %w[.yml .yaml].include?(path.extname) }
    all_workflows.map!(&:read)

    all_workflows.each do |workflow|
      workflow.each_line.grep(/^\s*-?\s*uses:/).each do |line|
        assert_match(/@[0-9a-f]{40}(?:\s+#.*)?$/, line)
      end
    end

    release_workflows = [
      read('.github/workflows/production-images.yml'),
      read('.github/workflows/deployment.yml')
    ]

    release_workflow = release_workflows.last
    assert_operator release_workflow.scan(/^\s*sbom:\s*true$/).length, :>=, 2
    assert_operator release_workflow.scan(/^\s*provenance:\s*mode=max$/).length, :>=, 2
    assert_equal 3, release_workflow.scan(/^\s*push:\s*false$/).length
    assert_equal false, release_workflow.include?('docker/login-action')
    assert_equal false, release_workflow.include?('DOCKERHUB_TOKEN')

    validation_workflow = release_workflows.first
    %w[deployApi.Dockerfile deployAppSvr.Dockerfile texlive.Dockerfile jplag.Dockerfile].each do |dockerfile|
      assert_includes validation_workflow, dockerfile
    end
    assert_equal false, validation_workflow.include?('paths:')
  end

  private

  def read(path)
    Rails.root.join(path).read
  end

  def locked_versions(name)
    read('Gemfile.lock')
      .scan(/^    #{Regexp.escape(name)} \((\d+(?:\.\d+)+)(?:-[^)]+)?\)$/)
      .flatten
      .map { |version| Gem::Version.new(version) }
      .uniq
  end
end
