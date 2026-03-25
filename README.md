Entra PIM Role Activator

A PowerShell-based GUI tool for securely activating Microsoft Entra Privileged Identity Management (PIM) roles using Microsoft Graph.

🚀 Features

- Clean and responsive Windows Forms GUI  
- Interactive Microsoft Graph authentication  
- Automatically loads eligible PIM roles  
- View currently active role assignments  
- Built-in role set presets  
- Multi-role activation support  
- Custom activation reason and duration  
- Real-time activity log  
- Automatic module installation and prerequisite checks  

📸 Screenshots

<img width="1245" height="952" alt="image" src="https://github.com/user-attachments/assets/d1be290b-cc4b-45d9-9395-cd1093a2443a" />



📋 Requirements

- Windows OS
- PowerShell 7 (recommended) or Windows PowerShell 5.1
- Internet access to Microsoft Graph
- Microsoft Entra account with:
- Eligible PIM roles
- Permission to activate those roles

📦 Microsoft Graph Dependencies

The script automatically installs/imports:

- Microsoft.Graph.Authentication
- Microsoft.Graph.Users
- Microsoft.Graph.Identity.DirectoryManagement
- Microsoft.Graph.Identity.Governance

🔐 Required Permissions (Scopes)

The tool requests:

- RoleManagement.ReadWrite.Directory
- RoleAssignmentSchedule.ReadWrite.Directory
- User.Read
- Organization.Read.All


📁 Project Structure

Entra-PIM-Role-Activator/

- Entra-PIM-Role-Activator.ps1
- Launch-Entra-PIM-Role-Activator.bat
- README.md
- LICENSE
- Logs (Created on First Use)

▶️ Getting Started

Option 1 — Run via launcher (recommended)

Double-click:

Launch-Entra-PIM-Role-Activator.bat

This will:

- Use PowerShell 7 if available
- Fall back to Windows PowerShell if needed
- Launch the GUI
- Option 2 — Run manually
- pwsh -ExecutionPolicy Bypass -STA -File .\Entra-PIM-Role-Activator.ps1

or:

- powershell -ExecutionPolicy Bypass -STA -File .\Entra-PIM-Role-Activator.ps1

⚙️ How It Works

- Launch the tool
- Click Connect
- Sign in with your Microsoft Entra account

The tool loads:
- Eligible PIM roles
- Active role assignments
- Tenant details
  
- Select roles
- Enter a reason
- Choose duration
- Click Activate Roles

🧠 Role Sets

Quick-select predefined groups of roles:

- Standard Access
- Intune / Endpoint
- Identity / Authentication
- Collaboration / M365
- Read Only / Audit
- All Eligible Roles
- Custom Selection

📝 Logging

- Logs are automatically written to:

.\Logs\

Each session generates a timestamped log file.

⚠️ Notes

- “Maximum Allowed” duration is not yet implemented
- Only eligible roles will be displayed
- Uses direct Microsoft Graph API calls
- No credentials are stored

🛠 Troubleshooting

- No roles showing
- Ensure your account has eligible PIM roles
- Click Refresh
- Activation fails
- Check the in-app log
- Review log files in /Logs
- Verify permissions and role eligibility

Modules won’t install
- Check internet access
- Ensure PowerShell Gallery is reachable

🔒 Security

- Uses secure Microsoft Graph authentication
- No credential storage
- Runs entirely in user context
- Review code before production use

🚧 Future Improvements

- Policy-based max duration support
- Role search/filter
- Export activation history
- Packaging as executable
- UI enhancements

📄 License

MIT License

Copyright (c) 2026 cloudwithusamah

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

⚠️ Disclaimer

- This tool is provided as-is without warranty.
- Test thoroughly before use in production environments.
