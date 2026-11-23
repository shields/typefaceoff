<!--
Copyright © 2026 Michael Shields

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# macOS platform APIs for the Typeface/Off redesign (verified against the offline Apple docs)

Method. Every item below was read through the `cupertino` CLI (apple-docs, hig,
samples) and the sqlite files behind it. Each item gives its cupertino URI.
"Avail" is the availability line as the index prints it. Statements marked
**unverified** were not found in the index. "Silent" means the page exists and
says nothing on the point.

Index limits that matter:

- The index was crawled May–June 2026. The highest `min_macos` value anywhere in
  `apple-documentation.db` is 26.5. No row has `min_macos` 27.x and no
  SwiftUI/AppKit page contains the string "macOS 27" (queried directly in
  sqlite).
- About 3,600 of 8,938 SwiftUI pages carry no availability line at all (they are
  stored in a different format). For those, "Avail: not stated" means the index
  cannot tell you, not that the symbol is old.
- A real macOS 27 source does exist: the **macOS Golden Gate 27 Beta Release
  Notes** (`apple-docs://macos-release-notes/macos-27-release-notes`, crawled
  2026-06-18). Section 4 uses it.

---

## 1. Window structure

### NavigationSplitView

- `struct NavigationSplitView<Sidebar, Content, Detail>`. Avail: macOS 13.0+.
  URI `apple-docs://swiftui/navigationsplitview`.
- Two-column `init(sidebar:detail:)`, three-column
  `init(sidebar:content:detail:)`. Each also has a `columnVisibility:` variant
  (macOS 13.0+) taking `Binding<NavigationSplitViewVisibility>`.
  `init(columnVisibility:preferredCompactColumn:sidebar:detail:)` is macOS 14.0+
  and only matters when collapsing to a stack.
- `NavigationSplitViewVisibility` values: `.automatic`, `.all`, `.doubleColumn`,
  `.detailOnly` (macOS 13.0+).
  `apple-docs://swiftui/navigationsplitviewvisibility`.
  - Caveat documented there: "Some platforms don't respect every option. For
    example, macOS always displays the content column."
- `navigationSplitViewColumnWidth(_:)` and
  `navigationSplitViewColumnWidth(min:ideal:max:)`. Avail: macOS 13.0+. Applied
  to the _content of a column_.
  `apple-docs://swiftui/view/navigationsplitviewcolumnwidth(min:ideal:max:)`.
- `navigationSplitViewStyle(_:)`: `.automatic`, `.balanced`, `.prominentDetail`.
  Avail: macOS 13.0+. `apple-docs://swiftui/view/navigationsplitviewstyle(_:)`.
  The pages do not say how the styles differ on macOS (silent).
- Sidebar toggle. `ToolbarDefaultItemKind.sidebarToggle` (macOS 14.0+) is
  documented as "the sidebar toggle toolbar item a NavigationSplitView adds by
  default", so the toggle is automatic. Remove it with
  `.toolbar(removing: .sidebarToggle)` applied inside the sidebar column (the
  doc example). `apple-docs://swiftui/toolbardefaultitemkind`,
  `apple-docs://swiftui/view/toolbar(removing:)` (Avail macOS 14.0+).
- `SidebarCommands` (macOS 11.0+) adds the View-menu show/hide sidebar commands
  when passed to `.commands`. Opt-in. `apple-docs://swiftui/sidebarcommands`.
- Silent: whether a hidden sidebar keeps its view state, and how the collapse is
  animated.
- HIG sidebars (`hig://general/sidebars`): "Consider letting people hide the
  sidebar." "Avoid hiding the sidebar by default to ensure that it remains
  discoverable." "In general, show no more than two levels of hierarchy." "Avoid
  putting critical information or actions at the bottom of a sidebar." On macOS,
  row height and icon size follow the General-settings sidebar icon size
  (small/medium/large).
- HIG split views (`hig://general/split-views`) call using split-view panes for
  functionality groups that supplement a main view "rare", with Keynote's
  navigator/notes/inspector around the slide canvas as the example. Sidebars are
  framed as navigation.

### inspector

- `func inspector<V>(isPresented: Binding<Bool>, @ViewBuilder content: () -> V) -> some View where V : View`.
  Avail: macOS 14.0+.
  `apple-docs://swiftui/view/inspector(ispresented:content:)`.
  - What it does: inserts an inspector "at the applied position in the view
    hierarchy"; presents as a trailing column in a regular size class and adapts
    to a sheet in compact.
  - Documented note: "Trailing column inspectors have their presentation state
    restored by the framework."
  - **Leading inspector: not documented.** The docs speak only of a "trailing
    column"; no edge parameter exists. A leading inspector would have to be
    built with `HSplitView` (or an AppKit `NSSplitViewController`).
  - **Does hidden inspector content keep its state? Silent.** Only the
    presented/not-presented flag is documented as restored. The Apple Landmarks
    sample (`swiftui-landmarks-building-an-app-with-liquid-glass`,
    `LandmarksSplitView.swift`) puts the inspector on the `NavigationSplitView`
    and keeps its model in an external `@Observable` (`ModelData`). Its content
    is `if let landmark = ... { Inspector } else { EmptyView() }`. It therefore
    does not demonstrate that view-local `@State`/disclosure/scroll state
    survives hiding. Assume it does not unless tested.
  - **No automatic toolbar button.** The Landmarks sample adds its own "Info"
    toolbar button that toggles the binding. `InspectorCommands` (macOS 14.0+,
    `apple-docs://swiftui/inspectorcommands`) adds a menu command with
    Control-Command-I when passed to `.commands`.
- `inspectorColumnWidth(_:)` (fixed) and `inspectorColumnWidth(min:ideal:max:)`.
  Avail: macOS 14.0+. Applied on the _content_ of the inspector.
  - `ideal` is the initial width absent state restoration and "influences the
    resulting width on macOS when a user double-clicks the divider".
  - Example in the docs: min 150, ideal 225, max 400, "at which point it will
    collapse, if allowed". `interactiveDismissDisabled(_:)` is the documented
    way to stop drag-collapse.
  - Caveat: "Only some platforms enable flexible inspector columns... SwiftUI
    may use a different width."
  - URIs: `apple-docs://swiftui/view/inspectorcolumnwidth(_:)`,
    `apple-docs://swiftui/view/inspectorcolumnwidth(min:ideal:max:)`.
- AppKit equivalent: `NSSplitViewItem(inspectorWithViewController:)` (macOS
  11.0+; macOS 14 gives inspectors "standard system default values" for its
  properties).
  `apple-docs://appkit/nssplitviewitem/init(inspectorwithviewcontroller:)`. The
  docs do not state an edge.

### HSplitView / VSplitView

- `struct HSplitView<Content>`. Avail: macOS 10.15+, macOS only.
  `init(content:)`. "Allows the user to resize [children] using dividers."
  `apple-docs://swiftui/hsplitview`.
- HIG split views (macOS): arrange panes vertically, horizontally or both. Set
  minimum and maximum pane sizes that keep the divider visible. "Prefer the thin
  divider style" (1 pt). Offer several ways to reveal a hidden pane (toolbar
  button, menu command with shortcut).
- Silent: how an `HSplitView` pane interacts with Liquid Glass
  sidebars/inspectors. It is a plain container, not a column of the split view
  that draws the glass sidebar.

### List, Table

- `List(selection:)` inside the sidebar column; `.listStyle(.sidebar)`. Avail:
  macOS 10.15+. Doc: "On macOS and iOS, the sidebar list style displays
  disclosure indicators in the section headers that allow the user to collapse
  and expand sections." `apple-docs://swiftui/liststyle/sidebar`.
- macOS 26 release notes
  (`apple-docs://macos-release-notes/macos-26-release-notes`, SwiftUI): "Section
  views without `isExpanded` binding are collapsible in a sidebar-styled List on
  macOS" (resolved issue).
- `struct Table`. Avail: macOS 12.0+. Selection and sort descriptors supported.
  `apple-docs://swiftui/table`. HIG lists-and-tables (macOS): sortable column
  headings, resizable columns, alternating row colours for multi-column tables,
  use an outline view for hierarchies.

### searchable

- `SearchFieldPlacement`: `.automatic`, `.toolbar`, `.toolbarPrincipal`,
  `.sidebar`, `.navigationBarDrawer`. Avail: macOS 12.0+.
  `apple-docs://swiftui/searchfieldplacement`. Doc: ".sidebar: The search field
  appears in the sidebar of a navigation view", and "Depending on the containing
  view hierarchy, SwiftUI might not be able to fulfill your request."
- `searchable(text:placement:prompt:)` Avail: macOS 12.0+ (String-prompt forms)
  / macOS 13.0+ (the `LocalizedStringResource`-prompt form).
- **macOS 26 behaviour change (release notes):** "On macOS, after linking new
  SDKs, the style of search fields with `SearchFieldPlacement.sidebar` is now
  fixed to the toolbar. Previously the search field would scroll as the first
  element in the list." Do not expect an in-list search row on macOS 26+.
- Other macOS search APIs: `searchToolbarBehavior(_:)` (`.automatic` macOS
  26.0+; `.minimize` is iOS/visionOS only), `searchPresentationToolbarBehavior`
  (macOS 14.1+), `searchFocused(_:)`,
  `DefaultToolbarItem(kind: .search, placement:)` (macOS 26.0+) to position the
  system search item.

---

## 2. Toolbar and title bar

### ToolbarItem placements (macOS behaviour as documented). `apple-docs://swiftui/toolbaritemplacement` (Avail macOS 11.0+)

| Placement                                                          | Doc statement for macOS                                                                                                                                                                                                                                                                                                                                                         |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.automatic`                                                       | Items go "in the current toolbar section in order of leading to trailing". Overflow: "If not all items fit... an overflow menu may be created."                                                                                                                                                                                                                                 |
| `.principal`                                                       | "In macOS... the system places the principal item in the center of the toolbar." "Key units of functionality that receive prominent placement."                                                                                                                                                                                                                                 |
| `.navigation`                                                      | "Leading edge of the toolbar ahead of the inline title if that is present."                                                                                                                                                                                                                                                                                                     |
| `.primaryAction`                                                   | **"In macOS... the location for the primary action is the leading edge of the toolbar."** (HIG toolbars, by contrast, says the primary action such as Done sits on the trailing side.)                                                                                                                                                                                          |
| `.secondaryAction`                                                 | Macos 13.0+. "Frequently used... not a requirement." No macOS location stated (silent).                                                                                                                                                                                                                                                                                         |
| `.status`                                                          | Macos 11.0+. "In macOS... the center of the toolbar." Informational, not an action.                                                                                                                                                                                                                                                                                             |
| `.confirmationAction`, `.cancellationAction`, `.destructiveAction` | For modal interfaces.                                                                                                                                                                                                                                                                                                                                                           |
| `.accessoryBar(id:)`                                               | "On macOS, items with an accessory bar placement are placed in a section below the title bar and toolbar area of the window. Each separate identifier will correspond to a separate accessory bar." Marked `@backDeployed(before: macOS 14.0)`. `apple-docs://swiftui/toolbaritemplacement/accessorybar(id:)`. The default button style there is `.accessoryBar` ("scope bar"). |
| `.title`, `.subtitle`, `.largeTitle`                               | Placements in the title area.                                                                                                                                                                                                                                                                                                                                                   |

HIG toolbars (`hig://general/toolbars`):

- Three areas: leading (sidebar toggle, title, document menu; not customisable),
  centre (common controls; customisable; collapses into overflow), trailing
  (important items, inspector-opening buttons, search, More menu).
- "The system automatically adds an overflow menu in macOS or iPadOS when items
  no longer fit. Don't add an overflow menu manually, and avoid layouts that
  cause toolbar items to overflow by default."
- Aim for at most three groups. Window titles under about 15 characters. "Don't
  title windows with your app name." Titles may be left empty.
- "Reduce the use of toolbar backgrounds and tinted controls." "Prefer using
  standard components." "Make every toolbar item available as a command in the
  menu bar."
- Keep text-labelled buttons separated by fixed space so they don't read as one.

### ToolbarSpacer

- `struct ToolbarSpacer`;
  `init(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic)`.
  Avail: **macOS 26.0+**. `apple-docs://swiftui/toolbarspacer`,
  `.../toolbarspacer/init(_:placement:)`, `apple-docs://swiftui/spacersizing`
  (macOS 26.0+).
  - `.fixed` splits glass groups; `.flexible` pushes items apart. Works inside
    `toolbar(id:)`. Landmarks sample uses it exactly so.
- `sharedBackgroundVisibility(_:)` on toolbar content. Avail: macOS 26.0+.
  "Toolbar items will be given a glass background effect that is shared with
  other items in the same logical grouping... Hiding the effect will cause the
  item to be placed in its own grouping."
  `apple-docs://swiftui/toolbarcontent/sharedbackgroundvisibility(_:)`.
- `DefaultToolbarItem(kind:placement:)`. Avail: macOS 26.0+.
  `apple-docs://swiftui/defaulttoolbaritem`.

### Customisation, removal, hiding

- `toolbar(id:content:)` with
  `ToolbarItem(id:placement:showsByDefault:content:)`. Avail: macOS 11.0+.
  `apple-docs://swiftui/view/toolbar(id:content:)`. Doc note: "Customizable
  toolbars will be displayed on both macOS and iOS, but only apps running on
  iPadOS 16.0 and later will support user customization." (This wording does not
  say macOS customisation is unsupported; HIG says "In iPadOS and macOS apps,
  consider letting people customize the toolbar".)
- `ToolbarCustomizationBehavior` (`.default`, `.disabled`, `.reorderable`),
  macOS 13.0+.
- `toolbar(removing:)` kinds: `.sidebarToggle`, `.search`, `.title` (macOS
  14.0+).
- `toolbarItemHidden(_:)` macOS 15.0+, for views inside a `ControlGroup` item.
  Adopting Liquid Glass: hide the whole toolbar item (`hidden(_:)`), not its
  view, or an empty item remains.
- `toolbarVisibility(_:for:)`, `toolbarBackgroundVisibility(_:for:)`,
  `toolbarBackground(_:for:)`: macOS 15.0+ (`Visibility` forms of the latter
  two), macOS 13.0+ for the `ShapeStyle` form. `ToolbarPlacement.windowToolbar`
  = "the containing window's toolbar, sometimes referred to as the titlebar"
  (`apple-docs://swiftui/toolbarplacement`). Doc: the preference "flows up to
  the nearest container that renders a bar... or the root view of a WindowGroup
  in macOS."
- `toolbarColorScheme(_:for:)`, `toolbarForegroundStyle(_:for:)` exist (Avail
  not shown in index).
- `ToolbarLabelStyle` (`.automatic`, `.iconOnly`, `.titleAndIcon`, `.titleOnly`)
  with scene modifiers `windowToolbarLabelStyle(fixed:)` / `(_:)`. Avail: macOS
  15.0+. `windowToolbarFullScreenVisibility(_:)` macOS 15.0+.
- `ToolbarTitleMenu`. Avail: macOS 13.0+. `toolbarTitleMenu(content:)`. A menu
  attached to the title; defaults to app commands (`saveItem`, `printItem`) or
  your own content.
- `ToolbarRole.editor`: macOS 13.0+ (`.browser` is iOS/visionOS only).

### Overflow

- Documented only as above ("an overflow menu may be created and remaining items
  placed in that menu"; HIG says the system adds it).
- Index has `ToolbarOverflowMenu`, `toolbarOverflowMenu(content:)` and
  `ToolbarItemVisibilityPriority` (`.low`, `.automatic`, `.high`,
  `init(lowerThan:)`, `init(higherThan:)`) with `visibilityPriority(_:)` on
  toolbar content. Doc: "items with a lower priority move first [into
  overflow]". **Availability is not stated in the index** for any of them,
  `ToolbarOverflowMenu`'s page only describes iOS/visionOS placement ("In iOS
  and visionOS, this content is placed into the overflow menu in the navigation
  bar"), and they are not in the macOS 26 or 27 release notes. Do not rely on
  them for a macOS 15 target.

### Title and subtitle

- `navigationTitle(_:)` macOS 11.0+ (String/Text forms),
  `navigationTitle(_: Binding<String>)` macOS 13.0+ ("allows editing the
  navigation title when the title is displayed in the toolbar").
  `apple-docs://swiftui/view/navigationtitle(_:)`.
- `navigationSubtitle(_:)`: macOS 11.0+ (some overloads macOS 13.0+). Doc: "On
  macOS, the primary destination's subtitle is displayed with the navigation
  title in the titlebar."
  `apple-docs://swiftui/view/navigationsubtitle(_:)-2h20t`.
- The documented sample (`swiftui-building-a-great-mac-app-with-swiftui`,
  `GardenDetail.swift`) uses `.navigationTitle(garden.name)` and
  `.navigationSubtitle(...)` with a toolbar.
- `toolbar(removing: .title)` hides the title (Landmarks does this on its detail
  view).

### Window toolbar style and title bar

- `windowToolbarStyle(_:)` is a **Scene** modifier. Avail: macOS 11.0+.
  `apple-docs://swiftui/scene/windowtoolbarstyle(_:)`. Styles
  (`apple-docs://swiftui/windowtoolbarstyle`):
  - `.automatic`
  - `.expanded`: "displays its title bar area above the toolbar"
  - `.unified` and `.unified(showsTitle:)`: "displays its toolbar and title bar
    inline"
  - `.unifiedCompact` and `.unifiedCompact(showsTitle:)`: "similar to unified,
    but with a more compact vertical sizing"
  - The index does not describe what any style looks like under macOS 26 glass
    (silent).
- `windowStyle(.hiddenTitleBar)`. Avail: macOS 11.0+. Doc: "hides both the
  window's title and the backing of the titlebar area, allowing more of the
  window's content to show." `apple-docs://swiftui/windowstyle/hiddentitlebar`.
  Alternatives: `.titleBar`, `.plain`.
- AppKit: `NSWindow.titlebarAppearsTransparent` (macOS 10.10+) "allows all
  content underneath it to show through. It only makes sense... when
  `fullSizeContentView` is also set." `NSWindow.backgroundColor` (macOS).
  `NSWindow.ToolbarStyle` (macOS 11.0+: automatic, expanded, preference,
  unified, unifiedCompact).
- `windowBackgroundDragBehavior(_:)` macOS 15.0+. `windowResizeAnchor(_:)` macOS
  26.0+.

### Is a segmented Picker in the toolbar the documented pattern?

- Apple's sample code does exactly that:
  `swiftui-building-a-great-mac-app-with-swiftui` `GardenDetail.swift` has
  `.toolbar { DisplayModePicker(mode: $mode) ... }`, and `DisplayModePicker` is
  a `Picker` with `.pickerStyle(SegmentedPickerStyle())` whose segments are
  `Label`s. This is sample-code evidence, not a documentation statement.
- HIG segmented controls (`hig://general/segmented-controls`), macOS: "Use a tab
  view in the main window area — instead of a segmented control — for view
  switching... Consider using a segmented control to help people switch views in
  a toolbar or inspector pane." Also: "Prefer using either text or images — not
  a mix of both", "no more than about five to seven segments", nouns for labels,
  tooltips for each segment, "introductory text" when icons are used.
- HIG toggles (macOS): "avoid using [switches, checkboxes, radio buttons] in a
  toolbar or status bar."
- macOS 27 beta: `TabsPickerStyle` / `.tabs` (see section 4) is the new style
  for pickers that represent tab-based navigation as opposed to value selection.

---

## 3. Appearance

### Light-only app

- `preferredColorScheme(_:)`.
  `func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View`. Avail:
  macOS 11.0+. `apple-docs://swiftui/view/preferredcolorscheme(_:)`. Doc: sets
  the scheme "for the nearest enclosing presentation, like a popover, a sheet,
  or a window. The value that you set overrides the user's Dark Mode selection
  for that presentation." So **yes, a SwiftUI window can be forced light** (or
  `nil` for no preference). `EnvironmentValues.colorScheme` (macOS 10.15+) is
  documented as read-only guidance: "possibly superseded by the configuration of
  the current presentation's view hierarchy". Whether _writing_ the environment
  value forces light controls in a sub-region is **not documented** (the page
  only shows reading).
- AppKit: `NSApplication.appearance` (macOS 10.14+, `NSAppearance?`; `nil`
  default means follow the system) and `NSWindow`/`NSView` `appearance` via
  `NSAppearanceCustomization`. Article
  `apple-docs://appkit/choosing-a-specific-appearance-for-your-macos-app`:
  "Views containing user-created content should always reflect the user's
  choices." "Choose an app-wide appearance only when required by your design"
  (photo editors forced dark so users focus on the photos). Assigning an
  appearance to a window or view makes children inherit it; works for popovers.
- Info.plist: `NSRequiresAquaSystemAppearance = YES` "causes the system to
  ignore the user's preference and always apply a light appearance", but the
  article frames it as a temporary opt-out ("If you need extra time to work on
  your app's Dark Mode support, you can temporarily opt out").
- HIG dark-mode: "Avoid offering an app-specific appearance setting." "In rare
  cases, consider using only a dark appearance" (immersive media, Stocks).
  "Soften the color of white backgrounds. If you display a content image that
  includes a white background, consider slightly darkening the image to prevent
  the background from glowing in the surrounding Dark Mode context." HIG
  dark-mode and color both say to test Increase Contrast and Reduce
  Transparency, separately and together, in both appearances.
- Net: light-only chrome is permitted but discouraged by the HIG. A paper-white
  specimen surface inside system-appearance chrome is not directly addressed.
  The documented tools for a light region are `preferredColorScheme` (whole
  presentation) or AppKit `appearance` on a hosted view.

### Tint and accent colour

- `tint(_:)`. `func tint(_ tint: Color?) -> some View`. Avail: macOS 12.0+
  (ShapeStyle overload macOS 15). Doc: "Unlike an app's accent color, which can
  be overridden by user preference, the tint color is always respected and
  should be used as a way to provide additional meaning to the control."
  `apple-docs://swiftui/view/tint(_:)`. This is the documented way to defeat the
  user's accent choice.
- `accentColor(_:)` (macOS 10.15+, in the deprecated list; `tint` is the
  replacement) and `Color.accentColor` (macOS 10.15+). Docs: set the app-level
  accent via the asset catalog. **"In macOS, SwiftUI applies customization of
  the accent color only if the user chooses Multicolor under General > Accent
  color."** `apple-docs://swiftui/color/accentcolor`.
- HIG color (macOS, "App accent colors"): "Beginning in macOS 11, you can
  specify an accent color to customize... buttons, selection highlighting, and
  sidebar icons. The system applies your accent color when the current value in
  General > Accent color settings is _multicolor_. If people set their accent
  color setting to a value other than multicolor, the system applies their
  chosen color... replacing your accent color. The exception is a sidebar icon
  that uses a fixed color you specify."
- Graphite: HIG dark-mode (macOS): with the graphite accent colour "macOS causes
  window backgrounds to pick up color from the current desktop picture...
  desktop tinting."
- Whether `.tint(.primary)` or a grey tint renders cleanly on all controls is
  not documented (unverified). macOS 26 release notes: `.bordered` buttons can
  be tinted with `tint(_:)` in apps adopting the new design;
  `buttonBorderShape(_:)` customises shape.
- System dynamic colours on macOS include `controlAccentColor` and
  `currentControlTint`.

### Window background, size

- `containerBackground(_:for:)` / `containerBackground(for:alignment:content:)`.
  Avail: macOS 14.0+. `ContainerBackgroundPlacement.window` (**macOS 15.0+**: "A
  background placement inside a Window or WindowGroup"); `.navigationSplitView`
  ("behind the content of a NavigationSplitView"); `.navigation`.
  `apple-docs://swiftui/containerbackgroundplacement`.
- `defaultSize(width:height:)` (macOS 13.0+), `windowResizability(_:)` (macOS
  13.0+: `.automatic`, `.contentSize`, `.contentMinSize` = "a minimum size that
  matches the minimum size of the window's content, no maximum size"). Doc
  example: `.frame(minWidth:..., maxWidth:...)` on content plus
  `.windowResizability(.contentSize)`.
- Adopting Liquid Glass: "Support arbitrary window sizes... Use split views to
  allow fluid resizing of columns."
- HIG macOS: avoid putting critical controls at the bottom edge of a window
  (windows are often dragged partly off-screen); avoid content in the camera
  housing region.

---

## 4. Liquid Glass (macOS 26+) and macOS 27

### What a rebuild gives

`apple-docs://technologyoverviews/adopting-liquid-glass`: "If your app uses
standard components from SwiftUI, UIKit, or AppKit, your interface picks up the
latest look and feel on the latest platform releases... build your app with the
latest SDKs." Standard bars, sheets, popovers and controls adopt the material
automatically; toolbars take a glass appearance with grouping; sidebars float in
the glass layer; controls get new shapes and sizes (Button, Toggle, Slider,
Stepper, Picker, TextField, and the NS equivalents) "if you... don't hard-code
their layout metrics"; sliders/toggles' knob becomes glass during interaction.
"Reduce your use of custom backgrounds in controls and navigation elements"
(check `NavigationSplitView`, `titleBar`, `toolbar(content:)`, `NSToolbar`,
`NSSplitView`). "Check for crowding or overlapping of controls."

### Opt-out key

- `UIDesignRequiresCompatibility` (Info.plist, Boolean). Avail: iOS/iPadOS/Mac
  Catalyst/macOS/tvOS 26.0+.
  `apple-docs://bundleresources/information-property-list/uidesignrequirescompatibility`.
  Doc: "Temporarily use this key while reviewing and refining your app's UI for
  the design in the latest SDKs. If YES, the system runs the app using a
  compatibility mode... as it looks when built against previous versions of the
  SDKs." Default is NO/absent. Whether the key still works on macOS 27 is **not
  stated** in this index (the macOS 27 notes do not mention it).

### APIs (all Avail macOS 26.0+ unless noted)

- `func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View`.
  Default shape is a capsule, anchored to the view's bounds.
  `apple-docs://swiftui/view/glasseffect(_:in:)`.
- `struct Glass`: `.regular`, `.clear`, `.identity`, `.tint(_:)`,
  `.interactive(_:)`. `apple-docs://swiftui/glass`.
- `GlassEffectContainer(spacing:content:)`: combines shapes and enables
  morphing; helps performance. With `glassEffectID(_:in:)` and
  `glassEffectUnion(id:namespace:)`.
  `apple-docs://swiftui/glasseffectcontainer`.
- `buttonStyle(.glass)` (`GlassButtonStyle`, macOS 26.0+; `.glass(_:)` with a
  `Glass` argument is **macOS 26.1+**) and `.glassProminent`
  (`GlassProminentButtonStyle`).
  `apple-docs://swiftui/primitivebuttonstyle/glass`. macOS 27 beta note:
  previously, glass buttons showed no hover state outside a toolbar; fixed.
- `scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set)`;
  styles `.automatic`, `.soft` ("a soft edge"), `.hard` ("a hard cutoff and
  dividing line"). `scrollEdgeEffectHidden(_:for:)`.
  `safeAreaBar(edge:alignment:spacing:content:)` registers a custom bar so the
  scroll edge effect applies ("extends the edge effect of any scroll views
  affected by the inset safe area"; horizontal edges only).
  `apple-docs://swiftui/scrolledgeeffectstyle`.
- `backgroundExtensionEffect()`. Doc: "The view will be duplicated into mirrored
  copies which will be placed around the view on any edge with available safe
  area. Additionally, a blur effect will be applied". "The most common use case
  is... a view in the detail column of a navigation split view so it can extend
  under the sidebar or inspector". "Apply this modifier with discretion... only
  a single instance." "This modifier will clip the view."
  `apple-docs://swiftui/view/backgroundextensioneffect()`. Landmarks article:
  align the view's leading and trailing edges to the container (no padding),
  apply the effect to the _image only_, then add overlays after it so text does
  not extend under the sidebar. Mechanism: take a sidebar-width strip, flip it
  horizontally, blur it, place it under the sidebar.
- AppKit: `NSGlassEffectView` (`.regular`, `.clear`),
  `NSBackgroundExtensionView` (macOS 26.0+; "can be laid out to extend outside
  the safe area, such as under the titlebar, sidebar, or inspector"),
  `NSSplitViewItem.automaticallyAdjustsSafeAreaInsets` (macOS 26.0+).

### What should NOT be glass (HIG materials, color, toolbars; Adopting Liquid Glass)

- "Don't use Liquid Glass in the content layer... use standard materials for
  elements in the content layer, such as app backgrounds. An exception...
  controls in the content layer with a transient interactive element like
  sliders and toggles."
- "Use Liquid Glass effects sparingly" on custom controls; limit to the most
  important functional elements. Avoid stacking or crowding glass.
- "Only use clear Liquid Glass for components that appear over visually rich
  backgrounds" (media); use regular for text-heavy components. If content under
  clear glass is bright, consider a 35% dark dimming layer.
- Colour: glass "has no inherent color, and instead takes on colors from the
  content directly behind it". "Apply color sparingly"; colour the background of
  a primary action rather than its symbol; "Refrain from adding color to the
  background of multiple controls". "If your app already has bright, colorful
  content in the content layer, prefer using the default monochromatic
  appearance of toolbars." "Avoid applying a similar color to toolbar item
  labels and content layer backgrounds."
- Toolbars: "use the content layer to inform the color and appearance of the
  toolbar, and use a ScrollEdgeEffectStyle when necessary to distinguish the
  toolbar area from the content area."
- Test with Reduce Transparency, Increase Contrast, Reduce Motion, and the
  user's preferred glass look: "These settings can remove or modify certain
  effects."

### macOS 27: what the documentation database actually contains

- **No macOS 27-only API in the symbol database.** Highest availability value
  indexed is 26.5; there is no `macOS 27.0` availability string in any SwiftUI
  or AppKit page (checked by sqlite and by full-text search; the only "27.0"
  hits are unrelated StoreKit/FoundationModels pages and the release notes
  themselves).
- The **macOS Golden Gate 27 Beta Release Notes** list the following relevant
  changes (all from `apple-docs://macos-release-notes/macos-27-release-notes`;
  treat as beta):
  - SwiftUI: "In apps built with the latest SDKs, the appearance of `TabViews`
    in inspectors now matches their appearance in sidebars, and in both contexts
    automatically uses the new `.tabs` picker style."
  - SwiftUI: `TabsPickerStyle` / `.tabs` "similar to the `.segmented` style, but
    VoiceOver reads it as 'tabs,' and on macOS it has a distinct visual
    appearance that distinguishes it from pickers that represent value
    selection". The type's own page (`apple-docs://swiftui/tabspickerstyle`)
    says the same and has no availability line.
  - AppKit: `NSSegmentedControl.role` with `NSSegmentedControlRole.tabs`, and
    `NSToolbarItemGroup.role` / `NSToolbarItemGroupRole`.
  - SwiftUI and AppKit: menu-bar and context menus hide menu item symbol images
    by default (apps linked on 26.0 and later); use `labelStyle(.titleAndIcon)`
    to keep an icon; AppKit `NSMenuItem.preferredImageVisibility`.
  - SwiftUI: "On macOS, the `Slider` implementation no longer uses `NSSlider`."
    Relevant to accessibility/automation queries that expect an NSSlider.
  - SwiftUI: disabled `.checkbox` toggles are no longer tinted; `LabeledContent`
    in a `Menu` maps its value to the menu item subtitle; `controlSize`,
    `buttonSizing`, `menuIndicatorVisibility`, `ButtonBorderShape` environment
    values are reset in sheets and popovers (fixed); selectable `Text` supports
    `TextRenderer`; the new `@State` macro implementation.
  - Known: "For some apps, the show/hide sidebar toolbar buttons are missing"
    (item 176879915).
- The earlier report's macOS 27 claims of a "user glass tint slider", "bordered
  toolbar items over the sidebar become glass", "uniform toolbars", and a
  "concentricity API" are **not found** in this database. `ConcentricRectangle`,
  `rect(corners:isUniform:)` and `cornerConfiguration` are referenced by name in
  Adopting Liquid Glass, so a concentricity API exists, but no macOS 27-only
  status is stated.

### macOS 26 release-note facts a designer needs (`apple-docs://macos-release-notes/macos-26-release-notes`, SwiftUI)

- "In `NavigationSplitView` and `TabView`s configured as `sidebarAdaptable`, the
  view trailing the sidebar's safe area is inset in the width of the sidebar. It
  can display content outside its safe area, underneath the sidebar."
- "In macOS, a `Form` of the `.grouped` style now has a more compact appearance
  when placed within a sidebar or inspector."
- `buttonSizing(_:)`: pickers/menus with button-like styles are now "fitted" by
  default on macOS 26; use `.buttonSizing(.flexible)` to fill the width.
- The default label style for macOS menu content is now `.titleAndIcon`.
- "A non-opaque window that hosts glass content will correctly update the
  backdrop behind the glass even if the window is inactive."

---

## 5. Controls and layout on macOS

| Item                                      | Declaration or style                                                                                                   | Avail (as indexed)                                                | macOS note                                                                                                                                                           |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Picker `.segmented`                       | `SegmentedPickerStyle`                                                                                                 | macOS 10.15+                                                      | See section 2                                                                                                                                                        |
| Picker `.menu`                            | `MenuPickerStyle`                                                                                                      | macOS 11.0+                                                       | pop-up appearance                                                                                                                                                    |
| Picker `.inline`                          | `InlinePickerStyle`                                                                                                    | macOS 11.0+                                                       |                                                                                                                                                                      |
| Picker `.radioGroup`                      | `RadioGroupPickerStyle`                                                                                                | macOS 10.15+ (macOS only)                                         | HIG: consider radio buttons for more than two mutually exclusive options                                                                                             |
| Picker `.palette`                         | `PalettePickerStyle`                                                                                                   | macOS 14.0+                                                       |                                                                                                                                                                      |
| Picker `.tabs`                            | `TabsPickerStyle`                                                                                                      | not stated; macOS 27 beta notes                                   | see section 4                                                                                                                                                        |
| Menu                                      | `Menu`; `menuStyle(_:)`; `ButtonMenuStyle`                                                                             | macOS 13.0+ for `ButtonMenuStyle`; `DefaultMenuStyle` macOS 11.0+ |                                                                                                                                                                      |
| `buttonStyle(.borderless)`                | `BorderlessButtonStyle`                                                                                                | macOS 10.15+                                                      |                                                                                                                                                                      |
| `menuIndicator(_ visibility: Visibility)` |                                                                                                                        | macOS 12.0+                                                       | hides the menu chevron                                                                                                                                               |
| Toggle `.checkbox`                        | `CheckboxToggleStyle`                                                                                                  | macOS 10.15+ (macOS only)                                         | HIG: checkbox for hierarchies; avoid switches/checkboxes in a toolbar                                                                                                |
| Toggle `.switch`                          | `SwitchToggleStyle`                                                                                                    | macOS 10.15+                                                      | HIG: switches emphasise settings; mini switch with `controlSize` in grouped forms                                                                                    |
| Toggle `.button`                          | `ButtonToggleStyle`                                                                                                    | macOS 12.0+                                                       |                                                                                                                                                                      |
| Slider                                    | `Slider(value:in:step:...)`                                                                                            | macOS 10.15+; `SliderTick` macOS 26.0+                            | HIG: label with colon, tick marks, live feedback                                                                                                                     |
| Stepper                                   | `Stepper`                                                                                                              | macOS 10.15+                                                      | HIG: Shift-click larger steps                                                                                                                                        |
| TextField with number format              | `TextField(_:value:format:prompt:)`                                                                                    | macOS 12.0+                                                       |                                                                                                                                                                      |
| `textFieldStyle`                          | `.plain`, `.roundedBorder`, `.squareBorder` (macOS only)                                                               | macOS 10.15+                                                      |                                                                                                                                                                      |
| LabeledContent                            | `LabeledContent`                                                                                                       | macOS 13.0+                                                       | "adapts to its container, like a form or toolbar"                                                                                                                    |
| Form styles                               | `.grouped` (`GroupedFormStyle`), `.columns` (`ColumnsFormStyle`), `.automatic`                                         | macOS 13.0+                                                       | `.grouped` more compact in sidebar/inspector on 26                                                                                                                   |
| Grid                                      | `Grid`/`GridRow`                                                                                                       | macOS 13.0+                                                       |                                                                                                                                                                      |
| DisclosureGroup                           |                                                                                                                        | macOS 11.0+                                                       | HIG disclosure triangles                                                                                                                                             |
| controlSize                               | `ControlSize`: `.mini`, `.small`, `.regular`, `.large`, `.extraLarge`                                                  | macOS 10.15+                                                      | `extraLarge` resolves to `.large` outside visionOS                                                                                                                   |
| popover                                   | `popover(isPresented:attachmentAnchor:arrowEdge:content:)`                                                             | macOS 10.15+                                                      | see below                                                                                                                                                            |
| sheet sizing                              | `presentationSizing(_:)`; `.form`, `.page`, `.fitted(...)`, `.sticky(...)`                                             | macOS 15.0+                                                       | `.form` on macOS "no floor is enforced, however a maximum proposed height is derived from the presenter height"                                                      |
| Arrow keys                                | `onMoveCommand(perform:)`                                                                                              | macOS 10.15+                                                      | arrow keys on a Mac keyboard                                                                                                                                         |
| Key presses                               | `onKeyPress(_:action:)`                                                                                                | macOS 14.0+                                                       | "key-down and key-repeat events", only while the view has focus                                                                                                      |
| Focus                                     | `focusable(_:)` (macOS 12.0+), `focusable(_:interactions:)` (macOS 14.0+), `focusSection()`, `focusEffectDisabled(_:)` |                                                                   | doc: on macOS button-like views conventionally accept focus only when keyboard navigation is enabled system-wide; custom views can use `.activate` interactions only |
| Hover                                     | `onHover(perform:)`                                                                                                    | macOS 10.15+                                                      | pointer enter/exit of the view's frame; a macOS 26 fix note says hover/`onContinuousHover` in an overlay interfered with gesture hit-testing                         |
| Magnify                                   | `MagnifyGesture`                                                                                                       | macOS 14.0+                                                       |                                                                                                                                                                      |
| Digits                                    | `monospacedDigit()`                                                                                                    | macOS 12.0+ (Text, View)                                          | Font and Text versions exist                                                                                                                                         |
| Font design/width                         | `Font.Design` (`.default`, `.serif`, `.rounded`, `.monospaced`), `Font.Width` via `.fontWidth(_:)`                     | macOS 10.15+ / 13.0+                                              |                                                                                                                                                                      |

- **Popover dismissal.** The SwiftUI popover page is **silent** on outside-click
  dismissal. Nearest documentation:
  - HIG popovers: "a popover generally closes when people click or tap outside
    its bounds or select an item in the popover"; if multiple selections are
    possible, keep it open until explicit dismissal or an outside click; "Always
    save work when automatically closing a nonmodal popover"; "Show one popover
    at a time"; on macOS, consider letting people detach a popover into a panel.
  - AppKit `NSPopover.Behavior`: `.transient` ("closes when the user interacts
    with a user interface element outside the popover"), `.semitransient`
    ("...elements in the window containing the popover's positioning view"),
    `.applicationDefined` (`apple-docs://appkit/nspopover/behavior-swift.enum`).
    Which behaviour SwiftUI's `popover` uses is **not documented**.
  - Doc note: on macOS the arrow edge "has always been respected"; omit
    `arrowEdge` (use the `attachmentAnchor`-only variant) to let the system
    choose.
  - macOS 26 fix: environment updates from outside a popover might not propagate
    into its content.
- **ScrollView zoom.** SwiftUI has no documented magnification parameter on
  `ScrollView`; `MagnifyGesture` is the SwiftUI tool. AppKit:
  `NSScrollView.allowsMagnification` (macOS 10.8+).
- **Control sizes.** HIG accessibility lists macOS minimum control sizes as
  28x28 pt and 20x20 pt (the index drops the row labels; the two values
  presumably are default and minimum). HIG: about 12 pt of padding around
  bezelled controls, 24 pt around bezel-less ones.
- **Reading note, HIG colour.** "Avoid relying solely on color to differentiate
  between objects... provide the same information in alternative ways" and
  "Convey information with more than color alone... red-green and blue-orange".
  Red/blue/black ink semantics therefore need a non-colour cue (labels, A/B
  legend text) in the chrome to meet the guidance.

---

## 6. Paper-white content under translucent bars

What the documentation offers, in order of fit:

1. **Safe-area extension is the built-in mechanism.** macOS 26 release notes:
   the detail view "can display content outside its safe area, underneath the
   sidebar" and the detail is inset by the sidebar width. Content that ignores
   the safe area (`ignoresSafeArea`) or a scroll view touching the
   sidebar/inspector edge scrolls under them ("the system automatically adjusts
   it to scroll under the sidebar or inspector and then off the edge"; Landmarks
   horizontal-scroll article).
2. **`backgroundExtensionEffect()`** mirrors and blurs a view into the safe-area
   regions of the sidebar, inspector (and the toolbar edge where there is safe
   area). On a pure-white view the mirrored, blurred copy is white, so it should
   read as paper continuing under glass. The docs only demonstrate it on images,
   require aligned unpadded edges, clip the view, and recommend a single use.
   Appearance on a flat white surface is **unverified**. AppKit twin:
   `NSBackgroundExtensionView`.
3. **Scroll edge effect.** Under the toolbar, the system applies an automatic
   scroll edge effect. `scrollEdgeEffectStyle(.soft | .hard, for:)` chooses a
   soft fade or a hard cutoff with dividing line; `.hard` is the documented
   option for a distinct dividing line. `scrollEdgeEffectHidden(_:for:)` removes
   it. `safeAreaBar` extends it to custom bars.
4. **Toolbar background visibility.**
   `toolbarBackgroundVisibility(_:for: .windowToolbar)` (macOS 15.0+) and
   `toolbarBackground(_:for:)` exist. Adopting Liquid Glass and HIG advise
   removing custom toolbar/split-view backgrounds so the system effect is not
   disturbed. Silent on what `.hidden` does under the glass toolbar on macOS 26.
5. **Window level.** `containerBackground(_:for: .window)` (macOS 15.0+) and
   `NSWindow.backgroundColor` set the window ground.
   `windowStyle(.hiddenTitleBar)` and `NSWindow.titlebarAppearsTransparent` +
   `fullSizeContentView` let content run behind the title bar.
6. HIG sidebars: "Extend visually rich content beneath the sidebar... either by
   letting it horizontally scroll or by applying a background extension effect."

Gap: nothing in the index shows a flat opaque light surface under a glass
sidebar in a dark-appearance window. Test it in a build.

---

## Corrections to an earlier draft written from memory

Contradicted by the docs:

1. **"The window toolbar ... `.primaryAction`" used for Undo/Swap/Match with the
   implication of trailing placement.** The `.primaryAction` doc says that on
   macOS "the location for the primary action is the leading edge of the
   toolbar." The HIG puts a single primary action like Done on the trailing
   side. Pin placements explicitly (`ToolbarSpacer`, `.navigation`,
   `.principal`) rather than assume.
2. **"Native collapse animation, `inspectorColumnWidth`, and a native toggle
   (`sidebar.trailing`) come for free" for `.inspector`.** There is no automatic
   inspector toolbar toggle; the Landmarks sample adds its own button, and only
   `InspectorCommands` (Control-Command-I) is built-in and opt-in. The sidebar
   toggle _is_ automatic for `NavigationSplitView`. The collapse animation is
   not documented.
3. **"`Color.accentColor` follows the system accent."** Only when the user's
   accent setting is Multicolor; otherwise the user's colour replaces the app
   accent. `tint(_:)` is the documented always-respected override.
4. **"Use `.glassEffect` ... for floating controls over the canvas, such as the
   Differences strip."** HIG materials says "Don't use Liquid Glass in the
   content layer" and to use it sparingly on custom controls. A strip drawn over
   the specimen canvas is arguably content layer; use a standard bar/inset
   instead.
5. **"That is how Preview and Pixelmator Pro treat documents, so it is
   acceptable" (white canvas in dark chrome) and "Give it a hairline border or a
   slight inset and shadow".** Not in the docs. The nearest HIG guidance is the
   opposite emphasis: "Soften the color of white backgrounds... slightly
   darkening the image to prevent the background from glowing". The AppKit
   appearance article does support forcing a specific appearance for views
   showing user content ("Views containing user-created content should always
   reflect the user's choices").
6. **macOS 27 claims** ("user glass tint slider", "bordered toolbar items over
   the sidebar become glass", "uniform toolbars", "concentricity API"). None
   found in this database. Verified macOS 27 items are the `.tabs` picker style,
   inspector/sidebar `TabView` appearance, menu symbol-image defaults, and the
   `Slider` implementation change (section 4).
7. **"Most of the new toolbar APIs (`visibilityPriority`, `toolbarOverflowMenu`)
   are described for iOS."** The pages exist (`ToolbarItemVisibilityPriority`,
   `ToolbarOverflowMenu`) with no availability line and no platform scope for
   `visibilityPriority`; only the overflow-menu page says anything
   platform-specific, and it names iOS/visionOS placement only. Treat as
   unconfirmed for macOS.

Confirmed (and upgraded from "from memory" to verified):

- `.inspector(isPresented:content:)`: macOS 14.0+, trailing column only, no
  leading variant, `inspectorColumnWidth(min:ideal:max:)` macOS 14.0+.
- `NavigationSplitView` macOS 13.0+; `.navigationTitle`/`.navigationSubtitle`
  macOS 11.0+; `ToolbarItem` placements `.principal`, `.navigation`,
  `.primaryAction`, `.secondaryAction`; `.formStyle(.grouped)` macOS 13.0+;
  `.presentationSizing` macOS 15.0+; `DisclosureGroup` macOS 11.0+;
  `controlSize` macOS 10.15+.
- `ToolbarSpacer` macOS 26.0+ ("as I recall" is now verified); `.glassEffect`,
  `GlassEffectContainer`, `.glass`/`.glassProminent`, `scrollEdgeEffectStyle`,
  `backgroundExtensionEffect()`: all macOS 26.0+.
- `UIDesignRequiresCompatibility`: temporary opt-out key, macOS 26.0+.
- Toolbar overflow: documented, and HIG says not to add your own overflow menu.
- "A segmented picker belongs in the toolbar": supported by Apple sample code
  and HIG ("a segmented control in a toolbar ... to help people switch views"),
  but HIG macOS also says a tab view is preferred for main-area view switching.
- Reduce Transparency / Increase Contrast / Reduce Motion testing: HIG color,
  dark-mode, materials, Adopting Liquid Glass.

Could not confirm (still unverified):

- That hidden `.inspector` content keeps view-local state. The docs say only
  that the presentation state is restored.
- `.regularMaterial` / `.bar` fallbacks for pre-26 (not looked up).
- That `.environment(\.colorScheme, .light)` forces light controls in a
  subregion (the docs show only reading it); `preferredColorScheme` is
  documented for a whole window/presentation.
- `HStack` with hand-built leading panel versus `HSplitView` interplay with
  glass sidebars.
- The detailed look of `.unified`, `.unifiedCompact`, `.expanded` window toolbar
  styles on macOS 26.
- How `backgroundExtensionEffect()` looks on flat white content.
