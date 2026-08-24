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

  def test_auto_uses_latest_testflight_version
    result = resolve(requested: "auto", testflight: %w[9.0.1 9.1.0], production: ["9.0.1"])

    assert_equal "9.1.0", result.fetch(:effective)
    refute result.fetch(:bumped)
  end

  def test_auto_uses_production_when_it_is_higher
    result = resolve(requested: "auto", testflight: ["9.1.0"], production: ["9.2.0"])

    assert_equal "9.2.0", result.fetch(:effective)
  end

  def test_lower_explicit_version_is_bumped
    result = resolve(requested: "9.0.1", testflight: ["9.1.0"], production: [])

    assert_equal "9.1.0", result.fetch(:effective)
    assert result.fetch(:bumped)
  end

  def test_higher_explicit_version_opens_new_train
    result = resolve(requested: "9.2.0", testflight: ["9.1.0"], production: [])

    assert_equal "9.2.0", result.fetch(:effective)
    refute result.fetch(:bumped)
  end

  def test_versions_are_compared_numerically
    result = resolve(requested: "auto", testflight: %w[9.2 9.10], production: [])

    assert_equal "9.10", result.fetch(:effective)
  end

  def test_existing_train_spelling_wins_for_equivalent_version
    result = resolve(requested: "9.1.0", testflight: ["9.1"], production: [])

    assert_equal "9.1", result.fetch(:effective)
  end

  def test_auto_without_existing_versions_fails
    error = assert_raises(AppStoreConnectRelease::Error) do
      resolve(requested: "auto")
    end

    assert_match "Provide an explicit app_version", error.message
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
end
