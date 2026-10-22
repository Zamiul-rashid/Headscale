from datetime import date, datetime

from labslots.slots import Slot, booking_covers, monday_of, next_slot, slot_at, week_slots


def test_slot_at_boundaries():
    assert slot_at(datetime(2026, 10, 19, 7, 59)) == Slot(date(2026, 10, 18), "night")
    assert slot_at(datetime(2026, 10, 19, 8, 0)) == Slot(date(2026, 10, 19), "day")
    assert slot_at(datetime(2026, 10, 19, 19, 59)) == Slot(date(2026, 10, 19), "day")
    assert slot_at(datetime(2026, 10, 19, 20, 0)) == Slot(date(2026, 10, 19), "night")


def test_night_slot_spans_midnight():
    s = slot_at(datetime(2026, 10, 20, 3, 0))
    assert s == Slot(date(2026, 10, 19), "night") and s.weekday == 0
    assert s.start == datetime(2026, 10, 19, 20) and s.end == datetime(2026, 10, 20, 8)


def test_next_slot_and_week():
    assert next_slot(Slot(date(2026, 10, 19), "day")) == Slot(date(2026, 10, 19), "night")
    assert next_slot(Slot(date(2026, 10, 25), "night")) == Slot(date(2026, 10, 26), "day")
    w = week_slots(monday_of(date(2026, 10, 22)))
    assert len(w) == 14 and w[0] == Slot(date(2026, 10, 19), "day") and w[-1].half == "night"


def test_booking_covers_respects_term_dates():
    s = Slot(date(2026, 10, 19), "day")
    assert booking_covers(0, "day", date(2026, 10, 1), date(2026, 12, 31), s)
    assert not booking_covers(0, "night", date(2026, 10, 1), date(2026, 12, 31), s)
    assert not booking_covers(0, "day", date(2026, 10, 20), date(2026, 12, 31), s)
