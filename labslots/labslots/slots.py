"""Slot arithmetic for the weekly 12-hour schedule in the proposal (proposal/proposal.tex).

Every PC has 14 slots a week: a day slot 08:00-20:00 and a night slot
20:00-08:00 (next morning) on each weekday. A night slot belongs to the
date it starts on, so Monday's night slot runs Mon 20:00 -> Tue 08:00.
All times are local (Asia/Dhaka by default).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

DAY_START = 8
NIGHT_START = 20
HALVES = ("day", "night")
WEEKDAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")


@dataclass(frozen=True)
class Slot:
    date: date
    half: str  # "day" | "night"

    @property
    def weekday(self) -> int:
        return self.date.weekday()

    @property
    def start(self) -> datetime:
        hour = DAY_START if self.half == "day" else NIGHT_START
        return datetime.combine(self.date, time(hour))

    @property
    def end(self) -> datetime:
        if self.half == "day":
            return datetime.combine(self.date, time(NIGHT_START))
        return datetime.combine(self.date + timedelta(days=1), time(DAY_START))

    @property
    def label(self) -> str:
        span = "08:00-20:00" if self.half == "day" else "20:00-08:00"
        return f"{WEEKDAYS[self.weekday]} {self.date:%d %b} {span}"


def slot_at(now: datetime) -> Slot:
    """The slot that contains `now` (naive local time)."""
    if now.hour >= NIGHT_START:
        return Slot(now.date(), "night")
    if now.hour < DAY_START:
        return Slot(now.date() - timedelta(days=1), "night")
    return Slot(now.date(), "day")


def next_slot(slot: Slot) -> Slot:
    if slot.half == "day":
        return Slot(slot.date, "night")
    return Slot(slot.date + timedelta(days=1), "day")


def monday_of(d: date) -> date:
    return d - timedelta(days=d.weekday())


def week_slots(monday: date) -> list[Slot]:
    """The 14 slots of the week starting on `monday`, in grid order."""
    return [Slot(monday + timedelta(days=i), half) for i in range(7) for half in HALVES]


def booking_covers(weekday: int, half: str, start: date, end: date, slot: Slot) -> bool:
    """Does a weekly booking (weekday/half within a term's dates) cover `slot`?"""
    return weekday == slot.weekday and half == slot.half and start <= slot.date <= end
