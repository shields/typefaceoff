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

# HIG research for the Typeface/Off redesign

Source: the offline `cupertino` HIG database. Every quote is verbatim from
`hig://general/<page>` and read in full. Pages dated June 2026 (Liquid Glass
era). Paraphrase is marked "(para.)". Opinions are marked **[Opinion]**. Nothing
here is from memory except where marked "unverified".

## 1. Components (macOS-relevant guidance, quoted)

### Sidebars `hig://general/sidebars`

- "A sidebar appears on the leading side of a view and lets people navigate
  between areas of your app or top-level collections of content, like folders
  and playlists."
- "Extend visually rich content beneath the sidebar... sidebars can float above
  content in the Liquid Glass layer."
- "Consider letting people hide the sidebar... in macOS, you can include a
  show/hide button or add Show Sidebar and Hide Sidebar commands to your app's
  View menu. ... Avoid hiding the sidebar by default to ensure that it remains
  discoverable."
- "In general, show no more than two levels of hierarchy in a sidebar. When a
  data hierarchy is deeper than two levels, consider using a split view
  interface that includes a content list between the sidebar items and detail
  view."
- "Group hierarchy with disclosure controls if your app has a lot of content."
- macOS: "A sidebar's row height, text, and glyph size depend on its overall
  size, which can be small, medium, or large. ... people can also change it by
  selecting a different sidebar icon size in General settings."
- macOS: "Consider automatically hiding and revealing a sidebar when its
  container window resizes."
- macOS: "Avoid putting critical information or actions at the bottom of a
  sidebar. People often relocate a window in a way that hides its bottom edge."
- "Make sure any sidebar icon colors you choose serve a clear purpose. By
  default, sidebar icons use your app's accent color... fixed colors can help
  clarify the meaning of an icon or draw attention to it."
- Note: the sidebar is documented as _navigation_ between "areas ... or
  top-level collections". A ranked list of characters is a _selection list_,
  which is closer to the middle pane of a three-pane split view, not a sidebar.
  **[Opinion]**

### Split views `hig://general/split-views`

- "A split view manages the presentation of multiple adjacent panes of
  content... Keynote in macOS uses split view panes to present the slide
  navigator, the presenter notes, and the inspector pane in areas that surround
  the main slide canvas." This is the closest HIG statement to this app's layout
  (list, canvas, inspector).
- "To support navigation, persistently highlight the current selection in each
  pane that leads to the detail view."
- macOS: "Set reasonable defaults for minimum and maximum pane sizes... make
  sure to use sizes that keep the divider visible."
- macOS: "Consider letting people hide a pane when it makes sense. If your app
  includes an editing area... consider letting people hide other panes to reduce
  distractions or allow more room for editing."
- macOS: "Provide multiple ways to reveal hidden panes... a toolbar button or a
  menu command — including a keyboard shortcut."
- macOS: "Prefer the thin divider style. The thin divider measures one point in
  width, giving you maximum space for content."
- "Consider letting people drag and drop content between panes."

### Panels and inspectors `hig://general/panels`

There is no separate Inspectors page in the database (see section 7). Inspectors
are covered in Panels.

- "An _inspector_ displays the details of the currently selected item,
  automatically updating its contents when the item changes or when people
  select a new item. In contrast, if you need to present an _Info_ window —
  which always maintains the same contents, even when the selected item changes
  — use a regular window, not a panel. Depending on the layout of your app, you
  might also consider using a split view pane to present an inspector."
- "Use a panel to give people quick access to important controls or information
  related to the content they're working with."
- "Prefer simple adjustment controls in a panel. As much as possible, avoid
  including controls that require typing text or selecting items to act upon
  because these actions can require multiple steps. Instead, consider using
  controls like sliders and steppers."
- "Write a brief title that describes the panel's purpose... macOS provides
  familiar panels titled 'Fonts' and 'Colors,' and many apps use the title
  'Inspector.'"
- Panel hides when the app is inactive; "avoid making a panel's minimize button
  available."
- HUD: "Prefer standard panels... use a HUD only: In a media-oriented app...;
  When a standard panel would obscure essential content". HUDs are dark and
  translucent, which suits neither a paper-white app nor a type tool.
- The `.inspector(isPresented:content:)` SwiftUI modifier exists:
  `apple-docs://swiftui/view/inspector(ispresented:content:)` (found by search,
  not read in depth).

### Toolbars `hig://general/toolbars`

- "A toolbar provides convenient access to frequently used commands, controls,
  navigation, and search."
- "Choose items deliberately to avoid overcrowding."
- "In iPadOS and macOS apps, consider letting people customize the toolbar...
  especially useful in apps that provide a lot of items — or that include
  advanced functionality that not everyone needs."
- "Reduce the use of toolbar backgrounds and tinted controls... use the content
  layer to inform the color and appearance of the toolbar."
- "Avoid applying a similar color to toolbar item labels and content layer
  backgrounds. If your app already has bright, colorful content in the content
  layer, prefer using the default monochromatic appearance of toolbars."
- "Prefer using standard components in a toolbar."
- "Prefer system-provided symbols without borders."
- "Minimize the number of groups... aim for a maximum of three."
- Trailing edge: "buttons that open nearby inspectors, an optional search field,
  and the More menu".
- Titles: "Don't title windows with your app name... keep the title under 15
  characters long". "If titling a toolbar seems redundant, you can leave the
  title area empty."
- macOS: "Make every toolbar item available as a command in the menu bar."
- "Consider temporarily hiding toolbars for a distraction-free experience."

### Windows `hig://general/windows`

- "Avoid creating custom window UI. System-provided windows look and behave in a
  way that people understand and recognize. Avoid making custom window frames or
  controls."
- macOS anatomy: "A macOS window consists of a frame and a body area... The
  frame... can include window controls and a toolbar. In rare cases, a window
  can also display a bottom bar."
- "Avoid putting critical information or actions in a bottom bar, because people
  often relocate a window in a way that hides its bottom edge."
- "Make sure that your windows adapt fluidly to different sizes."
- The explicit minimum/maximum window size guidance on this page is under
  visionOS only ("Choose a minimum and maximum size for each window"). I found
  no macOS minimum-window-size number.

### Popovers `hig://general/popovers`

- "Use a popover to expose a small amount of information or functionality...
  limit the amount of functionality in the popover to a few related tasks."
- "Consider using popovers when you want more room for content. Views like
  sidebars and panels take up a lot of space. If you need content only
  temporarily, displaying it in a popover can help streamline your interface."
- "Show one popover at a time... Never show a cascade or hierarchy of popovers."
- "Avoid making a popover too big." "Avoid using a popover to show a warning."
- macOS: "Consider letting people detach a popover... convert a popover into a
  panel."
- "Always save work when automatically closing a nonmodal popover."

### Sheets `hig://general/sheets`

- macOS: "Keep sheet interactions brief and occasional. Use a sheet only as a
  temporary interruption to the current workflow, and only to facilitate an
  important task. Avoid using a sheet to help people navigate your app's
  content."
- "Use a panel instead of a sheet if people need to repeatedly provide input and
  observe results."
- "Present a sheet in a default size that helps people retain their context.
  Avoid displaying a sheet that covers most or all of its window."
- Implication: a sheet is wrong for adjusting font settings, because that is
  repeated adjust-and-observe work. **[Opinion]**

### Pull-down and pop-up buttons

- Pop-up (`hig://general/pop-up-buttons`): "Use a pop-up button to present a
  flat list of mutually exclusive options or states." "Provide a useful default
  selection." "Give people a way to predict a pop-up button's options without
  opening it... an introductory label." "Consider using a pop-up button when
  space is limited and you don't need to display all options all the time." "If
  necessary, include a Custom option... to avoid cluttering the interface with
  items or controls that people need only occasionally."
- Pull-down (`hig://general/pull-down-buttons`): "Use a pull-down button to
  present commands or items that are directly related to the button's action."
  "Avoid putting all of a view's actions in one pull-down button. A view's
  primary actions need to be easily discoverable." "listing a minimum of three
  items can help the interaction feel worthwhile."
- Neither page addresses pickers over thousands of items (the font list). See
  section 7.

### Segmented controls `hig://general/segmented-controls`

- "Use a segmented control to provide closely related choices that affect an
  object, state, or view. For example, a segmented control in an inspector could
  let people choose one or more attributes."
- "Aim for no more than about five to seven segments in a wide interface."
- "Prefer using either text or images — not a mix of both."
- macOS: "Use a tab view in the main window area — instead of a segmented
  control — for view switching." and "Consider using a split view instead of a
  segmented control on screens that perform content filtering."
- macOS: "Consider using introductory text to clarify the purpose of a segmented
  control."
- So Text / Glyph / Languages mode switching: the HIG says tab view in the main
  area, or navigation via a split view/sidebar. A toolbar segmented control is a
  documented but second choice.

### Sliders `hig://general/sliders`

- "Consider supplementing a slider with a corresponding text field and stepper.
  Especially when a slider represents a wide range of values, people may
  appreciate seeing the exact slider value and having the ability to enter a
  specific value in a text field."
- macOS: "Consider giving live feedback as the value of a slider changes."
  (Dock-size example.)
- "Use tick marks to increase clarity and accuracy." "Prefer horizontal
  sliders." "Consider using a label to introduce a slider. Labels generally use
  sentence-style capitalization and end with a colon."

### Steppers `hig://general/steppers`

- "Make the value that a stepper affects obvious. A stepper itself doesn't
  display any values."
- "Consider pairing a stepper with a text field when large value changes are
  likely." macOS: "support Shift-click to change the value quickly."

### Text fields `hig://general/text-fields`

- "Use a text field to request a small amount of information"; "To let people
  input larger amounts of text, use a text view instead."
  (`hig://general/text-views` exists; sample text is the latter.)
- "Present a text field only when necessary. Whenever possible, prefer
  displaying a list of options rather than requiring text entry." (macOS)
- "Use a number formatter to help with numeric data."
- "Display a Clear button in the trailing end of a text field."

### Disclosure controls `hig://general/disclosure-controls`

- "Use a disclosure control to hide details until they're relevant. Place
  controls that people are most likely to use at the top of the disclosure
  hierarchy so they're always visible, with more advanced functionality hidden
  by default."
- "Provide a descriptive label when using a disclosure triangle... like
  'Advanced Options.'"
- Disclosure _button_: "Use no more than one disclosure button in a single
  view." (This limit is for buttons, not triangles.)

### Lists and tables, outline views

- `hig://general/lists-and-tables`: "Prefer displaying text in a list or table."
  "Keep item text succinct." "Use descriptive column headings." macOS: "let
  people click a column heading to sort", "Let people resize columns", "Consider
  using alternating row colors in a multicolumn table", "Use an outline view
  instead of a table view to present hierarchical data", "When possible, limit
  the number of rows."
- `hig://general/outline-views`: "Retain people's expansion choices", "Consider
  offering a search field... in a lengthy outline view", centered-ellipsis
  truncation.
- Table rows with a sortable "Difference" column fit the ranked-characters list.
  A ranked list is exactly "a table with a sort column". **[Opinion]**

### Search fields `hig://general/search-fields`

- iPadOS, macOS: "Put a search field at the trailing side of the toolbar for
  many common uses." "Include search at the top of the sidebar when filtering
  content or navigation there." "Include search as an item in the sidebar...
  when you want an area dedicated to discovery."
- "Use a scope bar to filter among clearly defined search categories." "Use
  tokens to filter by common search terms or items."
- Searchable font pickers are a case of "filtering content": search at the top
  of the list. **[Opinion]**

### Toggles `hig://general/toggles`

- macOS: "Use switches, checkboxes, and radio buttons in the window body, not
  the window frame. In particular, avoid using these components in a toolbar or
  status bar."
- "Use a checkbox instead of a switch if you need to present a hierarchy of
  settings."; "Prefer a switch for settings that you want to emphasize.";
  "Within a grouped form, consider using a mini switch"; "Consider using radio
  buttons if you need to present a set of more than two mutually exclusive
  options"; radio sets: "if you need to present more than about five options,
  consider using a component like a pop-up button."
- "To present a single setting that can be on or off, prefer a checkbox."
- Checkboxes with mixed state: "If you use a checkbox to globally turn on and
  off multiple subordinate checkboxes, show a mixed state" (relevant to linked
  A/B settings).

### Color wells, labels, scroll views

- Color wells (`hig://general/color-wells`): macOS click opens the system color
  picker. Not needed here (ink colors are fixed).
- Labels (`hig://general/labels`): "Use system-provided label colors to
  communicate relative importance." "Make useful label text selectable."
- Scroll views: "If you support zoom, set appropriate maximum and minimum scale
  values."

## 2. Color, dark mode, materials, Liquid Glass

### Appearance: is a light-only app acceptable?

- `hig://general/dark-mode`: "**Avoid offering an app-specific appearance
  setting.** An app-specific appearance mode option creates more work for people
  because they have to adjust more than one setting to get the appearance they
  want. Worse, they may think your app is broken because it doesn't respond to
  their systemwide appearance choice."
- "**Ensure that your app looks good in both appearance modes.** ... people can
  choose the Auto appearance setting, which switches between the light and dark
  appearances... potentially while your app is running."
- "**In rare cases, consider using only a dark appearance in the interface.**
  For example, it can make sense for an app that supports immersive media
  viewing to use a permanently dark appearance that lets the UI recede and helps
  people focus on the media."
- The HIG has no statement endorsing a _light-only_ app. The only sanctioned
  single-appearance case is dark-only for immersive media. A light-only whole
  app is outside the guidance.
- **[Opinion]** The defensible reading: the chrome (sidebar, toolbar, inspector)
  follows the system appearance, and only the _comparison canvas_ is permanently
  white, because shared ink must be black on white. This is a content surface
  like a page in Pages or a slide in Keynote (the HIG split-views page names
  Keynote's slide canvas). The dark-mode page also anticipates white content in
  dark UI: "Soften the color of white backgrounds. If you display a content
  image that includes a white background, consider slightly darkening the image
  to prevent the background from glowing in the surrounding Dark Mode context."
  That sentence is guidance to _soften_ white, which conflicts with a
  paper-white canvas whose colors are semantically defined. Treat it as a known
  tension, not support.
- "Test your content to make sure that it remains comfortably legible in both
  appearance modes... Dark Mode with Increase Contrast and Reduce Transparency
  turned on (both separately and together)."

### Color

`hig://general/color`:

- "**Avoid using the same color to mean different things.** Use color
  consistently... especially when you use it to help communicate information
  like status or interactivity." Applies directly: red, blue must never double
  as accent, error or selection. The app's accent should be neutral (graphite or
  the system accent kept off the canvas) so selection highlight is not confused
  with ink A/B. **[Opinion]**
- "**Make sure all your app's colors work well in light, dark, and increased
  contrast contexts.** ... If you define a custom color, make sure to supply
  light and dark variants, and..." (truncated at 700 chars when I extracted it;
  the rest of the sentence is in the page).
- "**Avoid relying solely on color to differentiate between objects, indicate
  interactivity, or communicate essential information.** ... be sure to provide
  the same information in alternative ways so people with color blindness or
  other visual disabilities can understand it. For example, you can use text
  labels or glyph shapes to identify objects or states." This is the key
  accessibility tension for the red/blue/black ink code (section 5).
- "**Avoid hard-coding system color values**", "**Avoid redefining the semantic
  meanings of dynamic system colors.**"
- "If your app lets people choose colors, prefer system-provided color controls
  where available."
- macOS accent (`#App-accent-colors`): "The system applies your accent color
  when the current value in General > Accent color settings is _multicolor_. If
  people set their accent color setting to a value other than multicolor, the
  system applies their chosen color... replacing your accent color. The
  exception is a sidebar icon that uses a fixed color you specify." So a user
  can set accent to red or blue and it would collide with ink meaning in
  controls (selection, focus). The canvas does not inherit accent, so the
  collision is limited to chrome. **[Opinion]**
- Liquid Glass color: "Apply color sparingly to the Liquid Glass material, and
  to symbols or text on the material." "Avoid using similar colors in control
  labels if your app has a colorful background... prefer a monochromatic
  appearance for toolbars and tab bars." "Be aware of the placement of color in
  the content layer. Make sure your interface maintains sufficient contrast by
  avoiding overlap of similar colors in the content layer and controls."

### Materials and Liquid Glass `hig://general/materials`

- "Liquid Glass forms a distinct functional layer for controls and navigation
  elements — like tab bars and sidebars — that floats above the content layer."
- "**Don't use Liquid Glass in the content layer.** ... use standard materials
  for elements in the content layer, such as app backgrounds. An exception...
  controls in the content layer with a transient interactive element like
  sliders and toggles."
- "**Use Liquid Glass effects sparingly.** ... Limit these effects to the most
  important functional elements in your app."
- "**Only use clear Liquid Glass for components that appear over visually rich
  backgrounds.**"
- macOS: "Prefer translucency to opaque colors in windows." Wording tension with
  a paper-white canvas; the canvas is content, not window material.
  **[Opinion]**
- `hig://general/layout`: "Differentiate controls from content... Instead of a
  background, use a scroll edge effect to provide a transition between content
  and the control area." "Extend content to fill the screen or window...
  Controls and navigation components like sidebars and tab bars appear on top of
  content rather than on the same plane."
- Consequence **[Opinion]**: the comparison canvas must not be glass. It is a
  flat white content surface. Glass belongs only to the toolbar and the sidebar
  or inspector chrome, and the system gives that for free with standard
  components.

## 3. Typography on macOS `hig://general/typography`

- "SF Pro is the system font in macOS. ... macOS doesn't support Dynamic Type."
- Default size 13 pt, minimum 10 pt on macOS.
- macOS built-in text styles (table verbatim): Large Title Regular 26/32
  (emphasized Bold); Title 1 Regular 22/26 (Bold); Title 2 Regular 17/22 (Bold);
  Title 3 Regular 15/20 (Semibold); Headline Bold 13/16 (Heavy); Body Regular
  13/16 (Semibold); Callout Regular 12/15 (Semibold); Subheadline Regular 11/14
  (Semibold); Footnote Regular 10/13 (Semibold); Caption 1 Regular 10/13
  (Medium); Caption 2 Medium 10/13 (Semibold). (size/line height in points)
- "In general, avoid light font weights... prefer Regular, Medium, Semibold, or
  Bold."
- Hierarchy: "Adjust font weight, size, and color as needed to emphasize
  important information and help people visualize hierarchy." "Minimize the
  number of typefaces you use, even in a highly customized interface. Mixing too
  many different typefaces can obscure your information hierarchy." (Chrome is
  SF; fonts A and B appear only on the canvas, plus font names in their own
  typeface only if shown as a preview. See opinion below.)
- "When necessary, use dynamic system font variants to match the text in
  standard controls." (`controlContentFont`, `labelFont`, `userFont`, etc.)
- **[Opinion]** Use SF Pro text styles throughout chrome: Headline for the A/B
  masthead names, Body for list rows, Subheadline or Callout for inspector row
  labels, Caption for metrics. Weight carries hierarchy (Regular vs Semibold),
  not many sizes.

## 4. Layout

- `hig://general/layout` (macOS section): "Avoid placing controls or critical
  information at the bottom of a window." "Avoid displaying content within the
  camera housing at the top edge of the window."
- "Make essential information easy to find by giving it sufficient space...
  don't obscure it by crowding it with nonessential details. You can make
  secondary information available in other parts of the window, or include it in
  an additional view."
- "Group related items... negative space, background shapes, colors, materials,
  or separator lines."
- "Align components with one another... Along with indentation, alignment can
  also help people understand an information hierarchy."
- "Take advantage of progressive disclosure."
- "Place items to convey their relative importance... most important items near
  the top and leading side of the window."
- `hig://general/designing-for-macos`: "Leverage large displays to present more
  content in fewer nested levels and with less need for modality, while
  maintaining a comfortable information density that doesn't make people strain
  to view the content they want." "Let people resize, hide, show, and move your
  windows to fit their work style and device configuration, and support
  full-screen mode." "Support personalization, letting people customize
  toolbars, configure windows to display the views they use most, and choose the
  colors and fonts they want." (Last phrase: the app's very purpose.)
- Hit targets, from `hig://general/accessibility` (Mobility): macOS "Default
  control size 28x28 pt, Minimum control size 20x20 pt". "Consider spacing
  between controls as important as size... about 12 points of padding around
  elements that include a bezel. For elements without a bezel, about 24 points
  of padding."
- Full screen `hig://general/going-full-screen` macOS: "Use the system-provided
  full-screen experience." "Always let people choose when to enter full-screen
  mode... Window's Enter Full Screen button, View menu item, or the
  Control-Command-F". "If necessary, adjust your layout in full-screen mode, but
  don't programmatically resize your window." "Continue to provide access to
  essential features and controls... without exiting full-screen mode."
- Window minimum sizes on macOS, spacing/margin numbers for macOS layouts, and
  density numbers: not found (section 7).

## 5. Accessibility `hig://general/accessibility`

- Contrast: "Strive to meet color contrast minimum standards." Table (WCAG AA):
  up to 17 pts, all weights: 4.5:1; 18 pts all weights: 3:1; any size Bold: 3:1.
  "If your app doesn't provide this minimum contrast by default, ensure it at
  least provides a higher contrast color scheme when the system setting Increase
  Contrast is turned on."
- `dark-mode`: "make sure the contrast ratio between colors is no lower than
  4.5:1. For custom foreground and background colors, strive for a contrast
  ratio of 7:1, especially in small text."
- "Convey information with more than color alone... people who are color blind
  may have particular difficulty with pairings such as red-green and
  blue-orange. Offer visual indicators, like distinct shapes or icons, in
  addition to color." Red versus blue on white is not one of the named bad
  pairs, but protan and deutan viewers see red as dark and low-chroma, so red
  and black on the canvas are hard to separate **[Opinion; the HIG does not say
  this]**. The HIG remedy is a non-color channel: text labels, glyph shapes. For
  this app that means: the legend names A and B in text, a mode that draws the
  overlay with outline or hatch or offset instead of fill, and per-character
  readouts ("only in A") in text. The app's own rule (red = A-only) should
  therefore never be the only way to learn which font owns a stroke.
- "Prefer system-defined colors": these have increased-contrast variants. Custom
  red and blue need explicit Increase Contrast variants. The HIG applies to
  custom colors too: "supply light and dark variants" (color page).
- Reduce Transparency and Increase Contrast are named only as test conditions in
  `dark-mode` and `color`; no macOS-specific behaviour spec was found beyond
  "test".
- Motion: "Be cautious with fast-moving and blinking animations... Reduce
  Motion".
- Keyboard: "Let people use the keyboard alone to navigate and interact with
  your app. ... Full Keyboard Access... Avoid overriding system-defined keyboard
  shortcuts." (`#Speech` section heading in the page, as extracted.)
  `hig://general/keyboards`: "Define custom keyboard shortcuts for only the most
  frequently used app-specific commands", modifier order Control, Option, Shift,
  Command; don't repurpose standard shortcuts. `segmented-controls` also warns:
  "Segments become selected when focus moves to them, not when people click
  them. ... Avoid putting other focusable elements close to segmented controls."
- "Support larger text sizes... enlarge text by at least 200 percent"; but macOS
  has no Dynamic Type (typography), so on macOS this is custom UI. Unverified
  how macOS apps are expected to meet 200%; the HIG gives no macOS mechanism.
- VoiceOver: "Describe your app's interface and content for VoiceOver." A canvas
  of glyph ink needs a text description (which fonts, which characters, counts
  of A-only/B-only/shared). **[Opinion]**

## 6. Document and canvas apps where chrome recedes

- No HIG page I found has a section on "content is the largest and brightest
  thing". The nearest quoted statements:
  - Split views: "Keynote in macOS uses split view panes to present the slide
    navigator, the presenter notes, and the inspector pane in areas that
    surround the main slide canvas."
  - Panels: "In general, a panel has a less prominent appearance than an app's
    main window."
  - Materials: Liquid Glass "allow[s] you to present controls and navigation
    without obscuring underlying content"; "Liquid Glass seeks to bring
    attention to the underlying content."
  - Toolbars: "Reduce the use of toolbar backgrounds and tinted controls... use
    the content layer to inform the color and appearance of the toolbar...
    without distracting from content."
  - Sidebars: "Consider letting people hide the sidebar... to create more room
    for content details or to reduce distraction."
  - Dark Mode (dark-only exception): a "permanently dark appearance that lets
    the UI recede and helps people focus on the media." The reverse case, a
    permanently bright content surface in a system-appearance UI, is not
    addressed.
  - Toolbars/full screen: "Consider temporarily hiding toolbars for a
    distraction-free experience."
  - Layout: "Extend content to fill the screen or window."
  - Designing for macOS: "Leverage large displays to present more content in
    fewer nested levels."

## 7. What I could not find

- No Inspectors page in the HIG database (`hig://general/inspectors` returns not
  found). Inspector guidance is in Panels (quoted above).
- No Title bars page (`hig://general/titlebars` not found). Title guidance is in
  Toolbars.
- No macOS minimum window size guidance (only visionOS). No numeric macOS
  margin/gutter/spacing spec (the macOS layout section has only two bullets).
  Density is addressed only in the quoted sentence from Designing for macOS.
- No guidance on pickers for very large lists (font lists), combo box specifics
  (`hig://general/combo-boxes` exists but I did not read it), or picker styles
  in a toolbar.
- No guidance endorsing a permanently light app or a permanently white canvas
  inside system-appearance chrome.
- No macOS-specific Increase Contrast / Reduce Transparency requirements beyond
  "test".
- No HIG statement on settings organization for dozens of per-item options
  (apart from disclosure controls, panels, and "Custom option" in pop-up
  buttons).
- No SwiftUI API signatures verified in this task; this report cites HIG only.
  Names mentioned from the HIG's own "Developer documentation" links
  (`NavigationSplitView`, `HSplitView`/`VSplitView`, `NSSplitViewController`,
  `backgroundExtensionEffect()`, `hudWindow`, `NSPanel`) are verified as links
  from the HIG pages; their availability and semantics are unverified here.
  `apple-docs://swiftui/view/inspector(ispresented:content:)` was found by
  search but not read.

## 8. What the HIG would have this app do (synthesis)

The structure the guidance points to is Keynote's: a split view whose panes
surround a central canvas, with an inspector pane and a toolbar, all standard
components. Items in **[Opinion]** are mine.

**(a) Picking two fonts.** HIG: "Present a text field only when necessary.
Whenever possible, prefer displaying a list of options" (text-fields, macOS).
macOS ships the precedent: a "Fonts" panel (panels page names it). Choose A and
B with two pop-up buttons or a searchable list, each with an introductory label
("Font A:", "Font B:") so "people can predict a pop-up button's options"
(pop-up-buttons). Search goes at the top of the list ("filtering content",
search-fields). **[Opinion]** Put the A and B pickers in the toolbar (center
area) or in a masthead above the canvas as the window's title content, each
preceded by an ink swatch plus a text name, so the identity of A and B is
carried by text and not only by color. A popover for the list is allowed
("Consider using popovers when you want more room for content") but must be a
single popover, not nested.

**(b) Ranked list of characters.** It is a table or list: "Prefer displaying
text in a list or table"; sortable columns, resizable columns; "persistently
highlight the current selection"; search field at top for filtering. It is the
middle or leading pane of a split view. **[Opinion]** Per the sidebar page's own
wording ("navigate between areas of your app or top-level collections"), I would
not call it a sidebar. Keep it a content list with a Difference column. When the
mode is Languages, the same pane holds the language list (outline view if script
grouping gives two levels, "no more than two levels"). One list pane serving
Glyph and Languages modes is the "split view with content list between sidebar
items and detail view" the HIG describes.

**(c) Large comparison canvas.** HIG: "Extend content to fill the screen or
window"; "Don't use Liquid Glass in the content layer"; "Differentiate controls
from content." The canvas is the detail pane, flat, white, edge to edge under
translucent toolbar. Hide-able side panes ("Consider letting people hide a
pane... reduce distractions") and full screen via the system
(Control-Command-F), no custom full-screen mode. **[Opinion]** The canvas is the
only permanently-light surface; all chrome follows the system appearance;
red/blue/black appear only on the canvas and in legend swatches, never in
controls, so "Avoid using the same color to mean different things" holds.

**(d) Dozens of per-font typography settings.** HIG: panels hold "quick access
to important controls... settings that affect the selected item"; inspector is
"a split view pane" or a panel; "Prefer simple adjustment controls... sliders
and steppers"; "supplement a slider with a text field and stepper" for wide
ranges; "Use a disclosure control to hide details until they're relevant... most
likely [used] controls at the top... advanced functionality hidden by default";
checkboxes (not switches) for hierarchies of settings; "mixed state" checkboxes
for A/B linked toggles; pop-up button with a "Custom" item for occasional rarely
used options; not a sheet (sheets are for "brief and occasional" interruptions,
and settings are repeated adjust-and-observe, which should be a "panel instead
of a sheet"). **[Opinion]** A trailing inspector pane (`inspector` modifier,
toggled by a toolbar button on the trailing edge, as the HIG toolbar page
describes: "buttons that open nearby inspectors") with two columns or a
segmented A / Link / B header: grouped DisclosureGroups ("Features",
"Variations", "Metrics"...), common settings at top, rare ones collapsed. Link
state per setting must be text-labelled (checkbox or labelled button), not only
a color change. Per-font settings in one table-like form where rows are settings
and columns A / B are the strongest alignment match for "Align components with
one another" and the user's stated row-by-row comparison.

**(e) Language list with detail pane.** Textbook split view: "selecting an item
in the view's primary pane displays the item's contents in the secondary pane";
"persistently highlight the current selection in each pane"; search at top of
the list; at most two hierarchy levels (script, then language) with disclosure
triangles. The detail pane shows the sample text on the canvas. Hyperglot data
and coverage live in the inspector. **[Opinion]**

**Window-level.** Standard window with a unified toolbar (title left empty or
short, "under 15 characters", not the app name), at most three toolbar groups,
every toolbar item also in the menu bar and View menu (Show/Hide Sidebar,
Show/Hide Inspector, with the title reflecting state), standard thin dividers,
no bottom bar for critical controls. Mode switching (Text / Glyph / Languages):
the HIG prefers navigation (sidebar or tab view) to a toolbar segmented control
for view switching, but permits segmented control for "closely related
subviews"; given three closely related views of the same comparison, a toolbar
segmented control with text labels is defensible. **[Opinion]**

**Accessibility.** Contrast 4.5:1 for text up to 17 pt in the chrome, 7:1 where
achievable; supply Increase Contrast variants for custom red/blue; add a
non-color channel for ink ownership and a text legend; keyboard alone must reach
every control and every list row; label the canvas for VoiceOver with counts.
**[Opinion on the specific remedies; HIG gives the principles quoted in section
5.]**
