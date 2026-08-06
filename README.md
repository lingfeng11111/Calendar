# Calendar

A personal iOS calendar focused on Chinese holidays, makeup workdays, solar terms, traditional festivals, and flexible personal schedules.

## Highlights

- Replaceable remote date-data providers with local caching and offline fallback.
- In-calendar annotations for makeup workdays, public holidays, solar terms, and festivals.
- Monthly overview and upcoming-date timeline for important dates.
- Custom vacations, annual leave, recurring dates, and local schedule items.
- Read-only Apple Calendar integration with explicit permission states.
- SwiftUI and SwiftData with stable Asia/Shanghai day identity.

## Requirements

- iOS 18 or later
- Xcode 26 or later

## Build

Open `CalendarApp.xcodeproj` in Xcode, select the `CalendarApp` scheme, choose an iOS Simulator or device, and run.

## Data strategy

Annual holiday and date-knowledge data is fetched through replaceable providers and cached locally. The app does not depend on a hard-coded annual holiday table.

## Status

Personal-use project under active development.
