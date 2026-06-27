require "rails_helper"

RSpec.describe PaySchedule, type: :model do
  describe "#pay_dates_for_month" do
    it "only returns dates inside the schedule window" do
      schedule = build(:pay_schedule,
        cadence: :monthly,
        first_pay_on: Date.new(2026, 3, 15),
        ends_on: Date.new(2026, 12, 31),
        day_of_month_one: 15)

      expect(schedule.pay_dates_for_month(Date.new(2026, 2, 1))).to eq([])
      expect(schedule.pay_dates_for_month(Date.new(2026, 3, 1))).to eq([ Date.new(2026, 3, 15) ])
      expect(schedule.pay_dates_for_month(Date.new(2026, 12, 1))).to eq([ Date.new(2026, 12, 15) ])
      expect(schedule.pay_dates_for_month(Date.new(2027, 1, 1))).to eq([])
    end

    it "includes the final pay date" do
      schedule = build(:pay_schedule,
        cadence: :semimonthly,
        first_pay_on: Date.new(2026, 1, 15),
        ends_on: Date.new(2026, 12, 30),
        day_of_month_one: 15,
        day_of_month_two: 30)

      expect(schedule.pay_dates_for_month(Date.new(2026, 12, 1))).to eq([
        Date.new(2026, 12, 15),
        Date.new(2026, 12, 30)
      ])
    end
  end

  describe ".active_during_month" do
    it "returns active schedules whose date window touches the month" do
      user = create(:user)
      current = create(:pay_schedule, user:, name: "Current", first_pay_on: Date.new(2026, 1, 15), ends_on: Date.new(2026, 12, 31))
      future = create(:pay_schedule, user:, name: "Future", first_pay_on: Date.new(2027, 1, 15))
      ended = create(:pay_schedule, user:, name: "Ended", first_pay_on: Date.new(2025, 1, 15), ends_on: Date.new(2025, 12, 31))
      disabled = create(:pay_schedule, user:, name: "Disabled", first_pay_on: Date.new(2026, 1, 15), active: false)

      expect(user.pay_schedules.active_during_month(Date.new(2026, 12, 1))).to contain_exactly(current)
      expect(user.pay_schedules.active_during_month(Date.new(2027, 1, 1))).to contain_exactly(future)
      expect(user.pay_schedules.active_during_month(Date.new(2025, 12, 1))).to contain_exactly(ended)
      expect(user.pay_schedules.active_during_month(Date.new(2026, 1, 1))).not_to include(disabled)
    end
  end

  describe "validations" do
    it "requires the final pay date to be on or after the first pay date" do
      schedule = build(:pay_schedule,
        first_pay_on: Date.new(2026, 3, 15),
        ends_on: Date.new(2026, 3, 14))

      expect(schedule).not_to be_valid
      expect(schedule.errors[:ends_on]).to include("must be on or after the first pay date")
    end
  end
end
