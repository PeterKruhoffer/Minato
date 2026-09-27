# Apple interface review

Reviewed against Apple’s Human Interface Guidelines on September 21, 2026. This is an implementation review, not an Apple certification.

| Apple guidance | Applied in Minato |
| --- | --- |
| [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) | A resizable native editor window, standard title and image metadata, menu commands, keyboard navigation, and more space for the screenshot. |
| [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) | An `NSToolbar` in the window frame, familiar SF Symbols, native tool selection, customization and overflow. Toolbar commands also appear in the menus. |
| [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) | An `NSSplitViewController` with resizable, collapsible side panels. Toolbar buttons and View menu commands show or hide them. Capture history uses a native table with keyboard selection and proportional thumbnails. |
| [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) | AppKit draws button states and focus rings. Stroke width and zoom use segmented controls. Dialog actions use title case and ellipses where more input is required. |
| [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode) and [Color](https://developer.apple.com/design/human-interface-guidelines/color) | The editor, settings, and note editor follow system appearance. Semantic colors and native materials respond to system preferences. The image-rendering palette is kept separate so export colors stay consistent. |
| [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) and [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) | Native tables expose selection, color swatches have names and checkmarks, annotation rows name their colors, and controls have labels/tooltips. Menu shortcuts focus each pane. Notes can be created at the image center and edited with the keyboard; selected annotations can be nudged by one or ten image pixels. |

The canvas remains a custom drawing view. Freehand drawing and placing arrows still require a pointing device; native controls and an accessible annotation list do not make spatial drawing fully operable with VoiceOver. The interface follows system contrast and transparency settings through AppKit colors and materials, but it has not undergone a comprehensive assistive-technology or localization audit.

Regression checks cover drawing without moving the window, automatic arrow color cycling, keyboard movement and undo, image-pixel sizing during resizing, split-pane reflow, and identical exports in light, dark, and high-contrast appearances. Visual checks use the sample image, not saved user captures.
