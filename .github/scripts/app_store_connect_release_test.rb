# frozen_string_literal: true

require "minitest/autorun"
require_relative "app_store_connect_release"

class AppStoreConnectReleaseTest < Minitest::Test
  def resolve(requested:, testflight: [], production: [])
    AppStoreConnectRelease.resolve_effective_version(
      requested: requested,
      testflight_versions: testflight,
      production_versions: production
    )
  end

  def test_requested_version_is_used_as_given
    result = resolve(requested: "9.2.0", testflight: ["9.1.0"], production: ["9.0.1"])

    assert_equal "9.2.0", result.fetch(:effective)
    assert_equal "9.1.0", result.fetch(:latest_testflight)
    assert_equal "9.0.1", result.fetch(:latest_production)
  end

  def test_version_below_testflight_but_above_production_is_allowed
    result = resolve(requested: "9.0.5", testflight: ["9.1.0"], production: ["9.0.1"])

    assert_equal "9.0.5", result.fetch(:effective)
  end

  def test_version_below_live_app_store_fails
    error = assert_raises(AppStoreConnectRelease::Error) do
      resolve(requested: "9.0.1", testflight: [], production: ["9.1.0"])
    end

    assert_match "not above the live App Store version 9.1.0", error.message
  end

  def test_version_equal_to_live_app_store_fails
    assert_raises(AppStoreConnectRelease::Error) do
      resolve(requested: "9.1.0", testflight: [], production: ["9.1"])
    end
  end

  def test_first_release_needs_no_existing_versions
    result = resolve(requested: "1.0.0")

    assert_equal "1.0.0", result.fetch(:effective)
    assert_nil result.fetch(:latest_testflight)
    assert_nil result.fetch(:latest_production)
  end

  def test_existing_train_spelling_wins_for_equivalent_version
    result = resolve(requested: "9.1.0", testflight: ["9.1"], production: [])

    assert_equal "9.1", result.fetch(:effective)
  end

  def test_exact_train_spelling_beats_equivalent_train
    result = resolve(requested: "9.1.0", testflight: %w[9.1 9.1.0], production: [])

    assert_equal "9.1.0", result.fetch(:effective)
  end

  def test_invalid_version_fails
    assert_raises(AppStoreConnectRelease::Error) do
      resolve(requested: "v9.1", testflight: ["9.0.0"])
    end
  end

  def test_next_build_number_starts_at_one
    assert_equal 1, AppStoreConnectRelease.next_build_number([])
  end

  def test_next_build_number_uses_highest_existing_number
    assert_equal 8, AppStoreConnectRelease.next_build_number(%w[1 7 3])
  end

  def test_non_integer_build_number_fails
    assert_raises(AppStoreConnectRelease::Error) do
      AppStoreConnectRelease.next_build_number(["1.2"])
    end
  end

  def test_release_channel_validation
    assert_equal "internal-only", AppStoreConnectRelease.validate_release_channel("internal-only")
    assert_equal "internal", AppStoreConnectRelease.validate_release_channel("internal")
    assert_equal "external", AppStoreConnectRelease.validate_release_channel("external")
    assert_raises(AppStoreConnectRelease::Error) do
      AppStoreConnectRelease.validate_release_channel("upload-only")
    end
  end

  def test_external_group_validation
    assert_equal "Public Beta", AppStoreConnectRelease.validate_external_group("Public Beta", ["Public Beta"])
    assert_raises(AppStoreConnectRelease::Error) do
      AppStoreConnectRelease.validate_external_group("Missing", ["Public Beta"])
    end
  end

  def test_live_app_store_version_accepts_new_state_attribute
    attributes = { "appVersionState" => "READY_FOR_DISTRIBUTION" }

    assert AppStoreConnectRelease.live_app_store_version?(attributes)
  end

  def test_live_app_store_version_accepts_deprecated_state_attribute
    attributes = { "appStoreState" => "READY_FOR_SALE" }

    assert AppStoreConnectRelease.live_app_store_version?(attributes)
  end

  def test_live_state_in_either_attribute_wins
    attributes = {
      "appVersionState" => "IN_REVIEW",
      "appStoreState" => "READY_FOR_SALE"
    }

    assert AppStoreConnectRelease.live_app_store_version?(attributes)
  end

  def test_paginator_collects_all_pages
    pages = {
      "first" => { "data" => [1], "links" => { "next" => "second" } },
      "second" => { "data" => [2], "links" => { "next" => nil } }
    }

    records = AppStoreConnectRelease::Paginator.collect("first") { |url| pages.fetch(url) }

    assert_equal [1, 2], records
  end

  def test_paginator_has_a_page_limit
    assert_raises(AppStoreConnectRelease::Error) do
      AppStoreConnectRelease::Paginator.collect("loop", max_pages: 2) do
        { "data" => [], "links" => { "next" => "loop" } }
      end
    end
  end

  def test_api_errors_are_reported
    error = assert_raises(AppStoreConnectRelease::Error) do
      AppStoreConnectRelease::Client.parse_response(500, '{"errors":[]}')
    end

    assert_match "HTTP 500", error.message
  end

  def test_rate_limits_and_server_errors_are_transient
    assert_raises(AppStoreConnectRelease::TransientError) do
      AppStoreConnectRelease::Client.parse_response(429, '{"errors":[]}')
    end
    assert_raises(AppStoreConnectRelease::TransientError) do
      AppStoreConnectRelease::Client.parse_response(503, '{"errors":[]}')
    end
  end
end
