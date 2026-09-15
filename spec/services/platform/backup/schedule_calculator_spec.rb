require "rails_helper"

RSpec.describe Platform::Backup::ScheduleCalculator do
  def schedule(**attributes)
    build(:backup_schedule, **attributes)
  end

  it "calculates a daily run in the configured time zone" do
    value = described_class.next_at(
      schedule(time_zone: "Eastern Time (US & Canada)", local_minute_of_day: 2 * 60),
      after: Time.utc(2026, 8, 26, 7)
    )

    expect(value).to eq(Time.utc(2026, 8, 27, 6))
  end

  it "runs only once across a repeated fall-back wall time" do
    value = described_class.next_at(
      schedule(time_zone: "Eastern Time (US & Canada)", local_minute_of_day: 90),
      after: Time.utc(2026, 11, 1, 5, 45)
    )

    expect(value).to eq(Time.utc(2026, 11, 2, 6, 30))
  end

  it "advances a nonexistent spring-forward wall time safely" do
    value = described_class.next_at(
      schedule(time_zone: "Eastern Time (US & Canada)", local_minute_of_day: 150),
      after: Time.utc(2026, 3, 8, 5)
    )

    expect(value.to_date).to eq(Date.new(2026, 3, 8))
    expect(value).to be > Time.utc(2026, 3, 8, 5)
  end

  it "calculates weekly and monthly eligibility" do
    weekly = schedule(cadence: "weekly", weekday: 1, local_minute_of_day: 60)
    monthly = schedule(cadence: "monthly", day_of_month: 28, local_minute_of_day: 60)

    expect(described_class.next_at(weekly, after: Time.utc(2026, 8, 26))).to eq(Time.utc(2026, 8, 31, 1))
    expect(described_class.next_at(monthly, after: Time.utc(2026, 8, 29))).to eq(Time.utc(2026, 9, 28, 1))
  end
end
