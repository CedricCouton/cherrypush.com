# frozen_string_literal: true

require "application_system_test_case"

class MetricsTest < ApplicationSystemTestCase
  let!(:user) { create(:user, name: "Yan Bonnel", email: "yan.bonnel@example.com", github_handle: "yanbonnel") }
  let!(:organization) { create :organization, user: user }
  let!(:project) { create(:project, user: create(:user), name: "rails/rails", organization: organization) }
  let!(:authorization) { create :authorization, user: user, organization: project.organization }
  let!(:eslint_metric) { create(:metric, project: project, name: "eslint") }
  let!(:eslint_report) { create(:report, metric: eslint_metric, value: 60, date: 4.days.ago) }
  let!(:rubocop_metric) { create(:metric, project: project, name: "rubocop") }
  let!(:rubocop_report) do
    create(
      :report,
      metric: rubocop_metric,
      value: 12,
      date: 1.day.ago,
      value_by_owner: {
        "@yanbonnel" => 10,
        "@rchoquet" => 8,
      },
    )
  end
  let!(:previous_report) do
    create(
      :report,
      metric: rubocop_metric,
      value: 9,
      date: 2.days.ago,
      value_by_owner: {
        "@yanbonnel" => 7,
        "@rchoquet" => 8,
      },
    )
  end

  let!(:occurrence_one) do
    create(
      :occurrence,
      text: "filepath:1",
      url: "permalink/filepath:2",
      report: rubocop_report,
      owners: ["@yanbonnel"],
      value: 1.2,
    )
  end

  let!(:occurrence_two) do
    create(
      :occurrence,
      text: "filepath:2",
      url: "permalink/filepath:2",
      report: rubocop_report,
      owners: %w[@yanbonnel @rchoquet],
      value: 2.8,
    )
  end

  let!(:contribution) do
    create(:contribution, metric: rubocop_metric, author_name: "Flavinho", commit_date: 1.week.ago, diff: -12)
    create(:contribution, metric: rubocop_metric, author_name: "Flavinho", commit_date: 1.week.ago, diff: -10)
  end

  it "applies filters to metrics" do
    sign_in(user, to: user_projects_path)
    find("tr", text: "rails/rails").click
    assert_text "eslint"
    fill_in "Filter metrics", with: "rubo"
    assert_no_text "eslint"
    find("tr", text: "rubocop").click

    # Recent Commmits
    assert_text "Recent Commits"
    assert_text "Flavinho"
    assert_text "1 week ago"

    # Top Contributors
    assert_text "Top Contributors"
    assert_text "Flavinho -22"

    # Occurrences
    assert_text "filepath:2 @yanbonnel, @rchoquet 2.8"
    assert_equal ["filepath:2 @yanbonnel, @rchoquet 2.8", "filepath:1 @yanbonnel 1.2"], all("tr").map(&:text).last(2)

    # Apply filters
    find("tr", text: "@rchoquet", match: :first).click
    fill_in("Filter by owners", with: "@rchoquet")
    find("li", text: "@rchoquet (8)").click
    assert_text "NAME OWNERS VALUE"
    assert_text "filepath:2 @yanbonnel, @rchoquet 2.8"

    # Profile does not show contributions from other users
    click_on "Avatar"
    find("li", text: "Yan Bonnel").click
    assert_text "Yan Bonnel"
    assert_text "@yanbonnel"
    assert_equal 1, all("tr").count

    # Profile shows contributions matching name, email, or github handle
    create(:contribution, author_name: "Yan Bonnel", metric: rubocop_metric, diff: 42)
    create(:contribution, author_email: "yan.bonnel@example.com", metric: rubocop_metric, diff: -12)
    create(:contribution, author_email: "yanbonnel@github-whatever.com", metric: rubocop_metric, diff: 36)
    refresh
    assert_text "+42"
    assert_text "-12"
    assert_text "+36"
  end

  it "allows users to follow and unfollow metrics" do
    sign_in(user, to: user_projects_path)
    find("tr", text: "rails/rails").click
    assert_text "eslint"
    fill_in "Filter metrics", with: "rubo"
    assert_no_text "eslint"
    find("tr", text: "rubocop").click
    click_on "Watch"
    assert_text "You're now watching this metric"
    click_on "Watching"
    find("li", text: "Unwatch").click
    assert_text "You're no longer watching this metric"
  end

  it "deletes metrics" do
    sign_in(user, to: user_projects_path)
    visit "/user/projects?project_id=#{project.id}&metric_id=#{eslint_metric.id}"
    assert_text "eslint"
    assert_equal 2, Metric.count
    sleep 1 # TODO: if we delete before fetching occurrences, then the occurence call will fail with record not found
    find("#metric-menu").click
    accept_confirm { find("li", text: "Delete this metric").click }
    assert_text "Metric deleted"
    assert_equal 1, Metric.count
  end
end
