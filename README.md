Entra PIM Role Activator

A PowerShell-based GUI tool for securely activating Microsoft Entra Privileged Identity Management (PIM) roles using Microsoft Graph.

🚀 Features

Clean and responsive Windows Forms GUI
Interactive Microsoft Graph authentication
Automatically loads eligible PIM roles
View currently active role assignments
Built-in role set presets for quick selection
Multi-role activation support
Custom activation reason + duration
Real-time activity log
Automatic module installation & prerequisite checks
📸 Screenshots

<img width="1245" height="952" alt="image" src="https://github.com/user-attachments/assets/d1be290b-cc4b-45d9-9395-cd1093a2443a" />



📋 Requirements
Windows OS
PowerShell 7 (recommended) or Windows PowerShell 5.1
Internet access to Microsoft Graph
Microsoft Entra account with:
Eligible PIM roles
Permission to activate those roles

📦 Microsoft Graph Dependencies

The script automatically installs/imports:

Microsoft.Graph.Authentication
Microsoft.Graph.Users
Microsoft.Graph.Identity.DirectoryManagement
Microsoft.Graph.Identity.Governance

🔐 Required Permissions (Scopes)

The tool requests:

RoleManagement.ReadWrite.Directory
RoleAssignmentSchedule.ReadWrite.Directory
User.Read
Organization.Read.All

📁 Project Structure
Entra-PIM-Role-Activator/
│
├── Entra-PIM-Role-Activator.ps1
├── Launch-Entra-PIM-Role-Activator.bat
├── README.md
├── LICENSE
├── .gitignore
│
├── docs/
│   └── screenshots/
│
└── Logs/

▶️ Getting Started
Option 1 — Run via launcher (recommended)

Double-click:

Launch-Entra-PIM-Role-Activator.bat

This will:

Use PowerShell 7 if available
Fall back to Windows PowerShell if needed
Launch the GUI
Option 2 — Run manually
pwsh -ExecutionPolicy Bypass -STA -File .\Entra-PIM-Role-Activator.ps1

or:

powershell -ExecutionPolicy Bypass -STA -File .\Entra-PIM-Role-Activator.ps1
⚙️ How It Works
Launch the tool
Click Connect
Sign in with your Microsoft Entra account
The tool loads:
Eligible PIM roles
Active role assignments
Tenant details
Select roles
Enter a reason
Choose duration
Click Activate Roles
🧠 Role Sets

Quick-select predefined groups of roles:

Standard Access
Intune / Endpoint
Identity / Authentication
Collaboration / M365
Read Only / Audit
All Eligible Roles
Custom Selection

📝 Logging

Logs are automatically written to:

.\Logs\

Each session generates a timestamped log file.

⚠️ Notes
“Maximum Allowed” duration is not yet implemented
Only eligible roles will be displayed
Uses direct Microsoft Graph API calls
No credentials are stored

🛠 Troubleshooting
No roles showing
Ensure your account has eligible PIM roles
Click Refresh
Activation fails
Check the in-app log
Review log files in /Logs
Verify permissions and role eligibility
Modules won’t install
Check internet access
Ensure PowerShell Gallery is reachable

🔒 Security
Uses secure Microsoft Graph authentication
No credential storage
Runs entirely in user context
Review code before production use

🚧 Future Improvements
Policy-based max duration support
Role search/filter
Export activation history
Packaging as executable
UI enhancements

📄 License

Recommended: MIT License

⚠️ Disclaimer

This tool is provided as-is without warranty.
Test thoroughly before use in production environments.
