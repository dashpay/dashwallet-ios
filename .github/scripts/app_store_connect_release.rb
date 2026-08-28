#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

module AppStoreConnectRelease
  class Error < StandardError; end
  class TransientError < Error; end

  class MarketingVersion
    include Comparable

    attr_reader :value

    def initialize(value)
      @value = String(value)
      unless @value.match?(/\A\d+(?:\.\d+){0,2}\z/)
        raise Error, "Invalid app version '#{@value}'. Expected one to three dot-separated integers."
      end

      @components = @value.split(".").map(&:to_i)
    end

    def <=>(other)
      padded_components <=> other.padded_components
    end

    protected

    def padded_components
      @components + Array.new(3 - @components.length, 0)
    end
  end

  class Paginator
    def self.collect(initial_url, max_pages: 50)
      records = []
      next_url = initial_url
      page_count = 0

      while next_url
        page_count += 1
        raise Error, "App Store Connect pagination exceeded #{max_pages} pages." if page_count > max_pages

        page = yield(next_url)
        records.concat(page.fetch("data"))
        next_url = page.dig("links", "next")
      end

      records
    end
  end

  LIVE_APP_STORE_STATES = %w[
    READY_FOR_DISTRIBUTION
    READY_FOR_SALE
  ].freeze

  module_function

  def validate_release_channel(channel)
    return channel if %w[internal-only internal external].include?(channel)

    raise Error, "Invalid release channel '#{channel}'. Expected 'internal-only', 'internal' or 'external'."
  end

  def validate_external_group(requested_group, groups)
    return requested_group if groups.include?(requested_group)

    available = groups.empty? ? "(none)" : groups.sort.join(", ")
    raise Error, "External TestFlight group '#{requested_group}' does not exist. Available groups: #{available}"
  end

  def live_app_store_version?(attributes)
    LIVE_APP_STORE_STATES.include?(attributes["appVersionState"]) ||
      LIVE_APP_STORE_STATES.include?(attributes["appStoreState"])
  end

  def maximum_version(values)
    values.map { |value| MarketingVersion.new(value) }.max
  end

  def resolve_effective_version(requested:, testflight_versions:, production_versions:)
    requested_version = MarketingVersion.new(requested)
    latest_testflight = maximum_version(testflight_versions)
    latest_production = maximum_version(production_versions)

    # Apple closes a version train once it ships to the App Store: a build
    # with the same or a lower version would be rejected at upload, so fail
    # here instead of after a two-hour archive.
    if latest_production && requested_version <= latest_production
      raise Error, "App version #{requested} is not above the live App Store version " \
                   "#{latest_production.value}. Pick a higher version."
    end

    # "9.1" and "9.1.0" are different trains to App Store Connect. A train
    # spelled exactly as requested always wins; failing that, an existing
    # TestFlight train that is numerically the same version lends its
    # spelling, so the upload continues that train instead of opening a
    # parallel one.
    existing_trains = testflight_versions.map { |value| MarketingVersion.new(value) }
    matching_train =
      existing_trains.find { |version| version.value == requested_version.value } ||
      existing_trains.find { |version| version == requested_version }

    {
      effective: (matching_train || requested_version).value,
      latest_testflight: latest_testflight&.value,
      latest_production: latest_production&.value
    }
  end

  def next_build_number(build_numbers)
    numbers = build_numbers.map do |value|
      string = String(value)
      unless string.match?(/\A\d+\z/)
        raise Error, "Build number '#{string}' is not a non-negative integer. Refusing to guess the next number."
      end

      string.to_i
    end

    (numbers.max || 0) + 1
  end

  class Client
    def self.parse_response(status, body)
      unless status.between?(200, 299)
        error_class = status == 429 || status >= 500 ? TransientError : Error
        raise error_class, "App Store Connect API returned HTTP #{status}: #{body}"
      end

      JSON.parse(body)
    rescue JSON::ParserError => e
      raise Error, "App Store Connect API returned invalid JSON: #{e.message}"
    end

    def initialize(key_id:, issuer_id:, private_key_path:)
      @key_id = key_id
      @issuer_id = issuer_id
      @private_key_path = private_key_path
      @token = nil
      @token_expires_at = 0
    end

    def find_app(bundle_id)
      url = api_url("/v1/apps", "filter[bundleId]" => bundle_id, "limit" => 1)
      app = get_json(url).fetch("data").first
      raise Error, "No App Store Connect app found for bundle ID #{bundle_id}." unless app

      app
    end

    def testflight_versions(app_id)
      pre_release_versions(app_id).filter_map do |version|
        version.fetch("attributes").fetch("version") if builds_for_pre_release_version(version.fetch("id")).any?
      end
    end

    def production_versions(app_id)
      url = api_url(
        "/v1/apps/#{app_id}/appStoreVersions",
        "filter[platform]" => "IOS",
        "limit" => 200
      )
      get_all(url).filter_map do |version|
        attributes = version.fetch("attributes")
        attributes.fetch("versionString") if AppStoreConnectRelease.live_app_store_version?(attributes)
      end
    end

    def external_group_names(app_id)
      url = api_url("/v1/betaGroups", "filter[app]" => app_id, "limit" => 200)
      get_all(url).filter_map do |group|
        attributes = group.fetch("attributes")
        attributes.fetch("name") unless attributes["isInternalGroup"]
      end
    end

    def build_numbers(app_id, version_string)
      version = pre_release_versions(app_id).find do |candidate|
        candidate.fetch("attributes").fetch("version") == version_string
      end
      return [] unless version

      builds_for_pre_release_version(version.fetch("id")).map do |build|
        build.fetch("attributes").fetch("version")
      end
    end

    def wait_for_build(app_id:, version_string:, build_number:, timeout_seconds:, interval_seconds:)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

      loop do
        begin
          version = pre_release_versions(app_id).find do |candidate|
            candidate.fetch("attributes").fetch("version") == version_string
          end
          if version
            build = builds_for_pre_release_version(version.fetch("id")).find do |candidate|
              candidate.fetch("attributes").fetch("version") == build_number
            end
            if build
              state = build.fetch("attributes")["processingState"]
              return build if state == "VALID"
              raise Error, "Uploaded build #{version_string} (#{build_number}) failed processing." if state == "FAILED"

              puts "Build #{version_string} (#{build_number}) is #{state || 'not processed yet'}; waiting..."
            else
              puts "Waiting for build #{version_string} (#{build_number}) to appear in App Store Connect..."
            end
          else
            puts "Waiting for TestFlight version #{version_string} to appear in App Store Connect..."
          end
        rescue TransientError, IOError, SystemCallError, SocketError,
               Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
          puts "Transient App Store Connect error while polling (#{e.class}: #{e.message}); retrying..."
        end

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          raise Error, "Timed out waiting for build #{version_string} (#{build_number}) to become valid."
        end

        sleep interval_seconds
      end
    end

    private

    def pre_release_versions(app_id)
      url = api_url(
        "/v1/preReleaseVersions",
        "filter[app]" => app_id,
        "filter[platform]" => "IOS",
        "limit" => 200
      )
      get_all(url)
    end

    def builds_for_pre_release_version(version_id)
      get_all(api_url("/v1/preReleaseVersions/#{version_id}/builds", "limit" => 200))
    end

    def get_all(url)
      Paginator.collect(url) { |page_url| get_json(page_url) }
    end

    def api_url(path, query = {})
      uri = URI("https://api.appstoreconnect.apple.com#{path}")
      uri.query = URI.encode_www_form(query) unless query.empty?
      uri.to_s
    end

    def get_json(url)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{authorization_token}"
      request["Content-Type"] = "application/json"
      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: true,
        open_timeout: 15,
        read_timeout: 30
      ) do |http|
        http.request(request)
      end
      self.class.parse_response(response.code.to_i, response.body)
    end

    def build_token
      private_key = OpenSSL::PKey.read(File.binread(@private_key_path))
      unless private_key.is_a?(OpenSSL::PKey::EC) && private_key.group.curve_name == "prime256v1"
        raise Error, "App Store Connect API key is not a P-256 EC key."
      end

      issued_at = Time.now.to_i
      @token_expires_at = issued_at + 1_200
      header = { alg: "ES256", kid: @key_id, typ: "JWT" }
      payload = {
        iss: @issuer_id,
        iat: issued_at,
        exp: @token_expires_at,
        aud: "appstoreconnect-v1"
      }
      signing_input = [header, payload].map { |part| base64url(JSON.generate(part)) }.join(".")
      der_signature = private_key.sign(OpenSSL::Digest::SHA256.new, signing_input)
      sequence = OpenSSL::ASN1.decode(der_signature)
      raw_signature = sequence.value.map do |integer|
        [integer.value.to_i.to_s(16).rjust(64, "0")].pack("H*")
      end.join
      "#{signing_input}.#{base64url(raw_signature)}"
    end

    def authorization_token
      if @token.nil? || Time.now.to_i >= @token_expires_at - 60
        @token = build_token
      end
      @token
    end

    def base64url(value)
      Base64.urlsafe_encode64(value, padding: false)
    end
  end

  class Command
    def initialize(arguments, env: ENV, output: $stdout)
      @arguments = arguments
      @env = env
      @output = output
    end

    def run
      command = @arguments.fetch(0) { raise Error, "Missing command." }
      client = Client.new(
        key_id: fetch_env("API_KEY_ID"),
        issuer_id: fetch_env("API_ISSUER_ID"),
        private_key_path: fetch_env("APP_STORE_CONNECT_API_KEY_PATH")
      )
      app = client.find_app(fetch_env("BUNDLE_ID"))
      app_id = app.fetch("id")

      case command
      when "resolve-version"
        resolve_version(client, app_id)
      when "resolve-build"
        resolve_build(client, app_id)
      when "assert-build-free"
        assert_build_free(client, app_id)
      when "wait-build"
        wait_build(client, app_id)
      else
        raise Error, "Unknown command '#{command}'."
      end
    end

    private

    def resolve_version(client, app_id)
      channel = AppStoreConnectRelease.validate_release_channel(fetch_env("RELEASE_CHANNEL"))
      requested = fetch_env("REQUESTED_VERSION")
      testflight_versions = client.testflight_versions(app_id)
      production_versions = client.production_versions(app_id)
      result = AppStoreConnectRelease.resolve_effective_version(
        requested: requested,
        testflight_versions: testflight_versions,
        production_versions: production_versions
      )

      if channel == "external"
        AppStoreConnectRelease.validate_external_group(
          fetch_env("TESTFLIGHT_GROUP"),
          client.external_group_names(app_id)
        )
      end

      if result.fetch(:effective) != requested
        @output.puts "::notice::Requested version #{requested} continues the existing TestFlight train #{result.fetch(:effective)}."
      end

      write_outputs(
        "requested_version" => requested,
        "latest_testflight_version" => result[:latest_testflight] || "none",
        "latest_production_version" => result[:latest_production] || "none",
        "effective_version" => result.fetch(:effective),
        "release_channel" => channel
      )
    end

    def resolve_build(client, app_id)
      version = fetch_env("EFFECTIVE_VERSION")
      build_numbers = client.build_numbers(app_id, version)
      next_number = AppStoreConnectRelease.next_build_number(build_numbers)
      write_outputs(
        "previous_build_number" => build_numbers.empty? ? "none" : build_numbers.map(&:to_i).max,
        "build_number" => next_number
      )
    end

    def assert_build_free(client, app_id)
      version = fetch_env("EFFECTIVE_VERSION")
      expected = fetch_env("BUILD_NUMBER")
      build_numbers = client.build_numbers(app_id, version)
      if build_numbers.include?(expected)
        next_number = AppStoreConnectRelease.next_build_number(build_numbers)
        raise Error, "Build #{version} (#{expected}) now exists. Re-run the workflow to use build #{next_number}."
      end

      @output.puts "Confirmed that TestFlight build #{version} (#{expected}) is available."
    end

    def wait_build(client, app_id)
      version = fetch_env("EFFECTIVE_VERSION")
      build_number = fetch_env("BUILD_NUMBER")
      build = client.wait_for_build(
        app_id: app_id,
        version_string: version,
        build_number: build_number,
        timeout_seconds: Integer(@env.fetch("WAIT_TIMEOUT_SECONDS", "1800")),
        interval_seconds: Integer(@env.fetch("WAIT_INTERVAL_SECONDS", "15"))
      )
      write_outputs(
        "id" => build.fetch("id"),
        "number" => build_number,
        "processing_state" => build.fetch("attributes").fetch("processingState")
      )
    end

    def fetch_env(name)
      value = @env[name]
      raise Error, "Missing environment variable #{name}." if value.nil? || value.empty?

      value
    end

    def write_outputs(values)
      values.each { |key, value| @output.puts "#{key}=#{value}" }
      output_path = @env["GITHUB_OUTPUT"]
      return if output_path.nil? || output_path.empty?

      File.open(output_path, "a") do |file|
        values.each { |key, value| file.puts "#{key}=#{value}" }
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    AppStoreConnectRelease::Command.new(ARGV).run
  rescue AppStoreConnectRelease::Error, KeyError, ArgumentError => e
    warn "::error::#{e.message}"
    exit 1
  end
end
