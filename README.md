# High Society (iOS, SwiftUI)

Native port of the web app. Needs Xcode 15+ and iOS 16+. Eight Swift files, no dependencies.

## Set up in Xcode (about 2 minutes)
1. Xcode > File > New > Project > iOS > App. Product Name: HighSociety. Interface: SwiftUI. Language: Swift. Save it anywhere.
2. In the project navigator, delete the generated `HighSocietyApp.swift` and `ContentView.swift` (Move to Trash).
3. Drag all eight files from the `HighSociety` folder here into the project (tick "Copy items if needed" and your app target).
4. Select the project, then the target, then General. Set Minimum Deployments to iOS 16.0.
5. Add the invite-link scheme: target > Info > URL Types > + . Set Identifier to your bundle id and URL Schemes to `highsociety`. (XcodeGen does this for you.)
6. Choose an iPhone simulator or your phone and press Run. For a real phone, set your Team under Signing & Capabilities.

## Or use XcodeGen
`brew install xcodegen`, run `xcodegen` in this folder, then open `HighSociety.xcodeproj`.

## Files
- Engine.swift: cards, the 11 contracts, set/run validation, solver, turn flow, scoring, computer player
- GameStore.swift: app state, saving, lay-down draft, computer-player turn loop
- CardViews.swift, Theme.swift: card drawing, colours (light and dark)
- Screens.swift: setup, table, lay-down, scores and play-by-play, round end, final
- OnlineClient.swift: server calls and wire types
- OnlineScreens.swift: host/join panel, invite-link sheet, lobby
- HighSocietyApp.swift: app entry point

## Online play Work in Progress

The game saves itself to UserDefaults and resumes where you left off.
