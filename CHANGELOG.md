# XIVExp

## 0.3.3

### Fixes
- An experience message the game hides from add-ons no longer causes an error, and neither does being at the level cap when the game hides that.
- Text with more than six words now keeps updating (it stopped).

### Under the hood
- Text templates and the text's light tint are FrogLib's, shared with the other Frog Wizard add-ons.

## 0.3.2

### Under the hood
- Shares its options page and its texture and font lists with the other Frog Wizard add-ons (one copy of the code, so a fix reaches them all at once). Nothing changes in how it looks or works.

## 0.3.1

### Options
- Listed with the rest of Frog Wizard's add-ons: under a "Frog Wizard" heading in the AddOn list, and in its own "Frog Wizard" section of Options > AddOns, whose page lists them all with a button to each one's settings.

## 0.3.0

### Leveling info
- New text on the right under the bar, "14 kills   1h 20m" by default: how many kills to level (from your last few kills, rested bonus included) and how long to level at your pace this session. Change it on the Text tab with the words tolevel, perhour (XP an hour), eta and quests (XP in finished quests you haven't handed in), or leave it empty to hide it.
- XP waiting in finished quests shows on the bar too, as an orange stretch after your XP (like rested XP in blue), so you can see how far handing them in takes you. It can be turned off or recoloured on the Text tab.

### Fixes
- Fixed a "file not found" font error after EllesmereUI is turned off or removed while its font (Expressway) is chosen. The game's standard font is used until you pick another.

## 0.2.1

- No changes in the game. From this version, releases are published automatically to CurseForge as well as GitHub.

## 0.2.0

### Reputation
- The reputation you watch ("Show as Experience Bar" in the Reputation tab) gets its own gauge above the XP bar, with the faction's initials, your standing and your progress: "AD Friendly 2,400/6,000". It's coloured by standing, and at Exalted shows just the faction and standing.
- At max level with "Hide at max level" on, it takes the XP bar's place.
- New Reputation tab in the settings: turn it off, change its text (words: short, name, standing, value, max, percent) or give it a fixed colour.

### Blizzard's bars
- Blizzard's XP bar is now hidden, and so is its reputation bar while XIVExp shows yours. Each has its own setting to bring it back. The space they took stays empty.

## 0.1.2

### Options
- Now listed in the game's Options > AddOns, with a button that opens its settings and a list of its slash commands.

### Fixes
- Fixed a "forbidden object" error that could appear when status-effect text updated in restricted content (for example in combat).
