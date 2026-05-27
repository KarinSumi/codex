# Manual Nanobanana Simulation Guide

This document records the exact steps to simulate a human generating images/videos via Gemini using the `agent-browser` headless tool. Use this as a reference to recreate the flow or to build automation.

## 1. Preparation
Ensure you have `agent-browser` installed and your Chrome "Default" profile is logged into `gemini.google.com`.

## 2. Launch Browser
```bash
npx agent-browser close
npx agent-browser --profile Default --download-path ~/nanobanana_tmp open https://gemini.google.com/app
```
*Wait ~10-15 seconds for the page to load.*

## 3. Bypass Login (Simulate Auto-Login)
Check for a "Sign in" button. Clicking it usually triggers the saved session in your profile.
```bash
# Get references
npx agent-browser snapshot -i
# Click the Sign-in link/button (e.g., @e1)
npx agent-browser click @e1
```
*Wait ~10 seconds for the dashboard to appear.*

## 4. Select the Media Tool
You can either click the tool icon on the dashboard or open the "Tools" menu.
```bash
# Dashboard method (if visible)
npx agent-browser find role button click --name 'Create image'

# Menu method (if icon is hidden)
npx agent-browser click @tools_button_ref
npx agent-browser find role button click --name 'Create image'
```

## 5. Submit Prompt
```bash
# Fill the textbox
npx agent-browser find role textbox fill "Your descriptive prompt here" --name 'Enter a prompt for Gemini'
# Click Send
npx agent-browser find role button click --name 'Send message'
```

## 6. Monitor Generation
Generation usually takes 30-120 seconds. Monitor using snapshots:
```bash
npx agent-browser snapshot -i
```
Look for:
- "Creating your image..." (Status)
- "Good response" / "Bad response" (Indicates generation is finished)
- "Download full size image" (The target button)

## 7. Download and Save
```bash
# Click download
npx agent-browser find role button click --name 'Download full size image'

# Move from temp to permanent folder
ls -la ~/nanobanana_tmp
mv ~/nanobanana_tmp/*.png ~/generate-picture/
```

## 8. Debugging
If the UI doesn't behave as expected:
```bash
npx agent-browser screenshot debug.png
npx agent-browser snapshot > full_dom.txt
```
