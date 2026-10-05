# Intune Application Packaging & ServiceNow Automation Pipeline

**Repository Name:** `intune-application-packaging-dev`  
**Architecture:** ServiceNow Dev $\leftrightarrow$ GitHub Actions Dev $\leftrightarrow$ Microsoft Intune Dev  
**Initial Pilot App:** Notepad++ (`v8.6.5`)  
**Date:** 05 October 2026  

---

## 📖 Executive Summary & System Architecture

Is repository me **Microsoft Intune Application Packaging & Onboarding** ko **ServiceNow Dev** ke saath bidirectional integration dwara automate karne ka complete implementation code aur workflow shamil hai.

Jab ServiceNow Dev me koi **Catalog Task (SCTASK)** approve hota hai, to ek automated webhook (`repository_dispatch`) GitHub Actions workflow ko trigger karta hai. GitHub Actions automatic target application ko download karta hai, SHA256 integrity verify karta hai, `.intunewin` package build karta hai, Intune Dev tenant me upload/assign karta hai, aur status (Success / Failure + Log URL) ServiceNow ko wapas bhejta hai.

```
                      +---------------------------------+
                      | ServiceNow Dev Instance         |
                      | (SCTASK Raised & Approved)      |
                      +---------------------------------+
                                      |
                                      | 1. Outbound REST Payload (repository_dispatch)
                                      v
                      +---------------------------------+
                      | GitHub Actions (Dev Repo)       |
                      | Workflow: package-app.yml       |
                      | - Parse Payload & Manifest      |
                      | - Download & Verify SHA256 Hash |
                      | - Build .intunewin Package      |
                      +---------------------------------+
                                      |
                                      | 2. Microsoft Graph API
                                      v
                      +---------------------------------+
                      | Microsoft Intune (Dev Tenant)   |
                      | - Publish Package & Assign UAT  |
                      +---------------------------------+
                                      |
                                      | 3. Inbound Webhook Callback
                                      v
                      +---------------------------------+
                      | ServiceNow Webhook Receiver     |
                      +---------------------------------+
                                      |
                      +---------------+---------------+
                      |                               |
              [ YES: Successful ]             [ NO: Failed ]
                      |                               |
                      v                               v
         +--------------------------+    +--------------------------+
         | SCTASK Auto-Closed       |    | SCTASK State: On Hold    |
         | Requestor Notified       |    | Attach GitHub Run URL    |
         +--------------------------+    +--------------------------+
```

---

## 📁 Repository Directory Structure

```text
intune-application-packaging-dev/
├── .github/
│   └── workflows/
│       └── package-app.yml           # Main GitHub Actions CI/CD Pipeline (With Line-by-Line Comments)
├── manifests/
│   └── notepadplusplus.json         # Pilot Application Manifest (Notepad++ Config)
├── scripts/
│   ├── Invoke-PackagingPipeline.ps1  # PowerShell Packaging Script (Download, Hash, .intunewin)
│   └── Send-ServiceNowWebhook.ps1   # PowerShell Script for ServiceNow Real-time Callback
└── README.md                         # Master Step-by-Step Technical Documentation
```

---

## ⚙️ Step 1: Prerequisites & GitHub Secrets Configuration

Pipeline run karne se pehle GitHub Repository Settings me nimnlikhit **Secrets** add karein (`Settings -> Secrets and variables -> Actions`):

| Secret Name | Purpose & Description | Example Value |
| :--- | :--- | :--- |
| `SNOW_DEV_INSTANCE_URL` | ServiceNow Dev Instance URL | `https://dev12345.service-now.com/api/custom/intune_webhook` |
| `SNOW_DEV_API_TOKEN` | ServiceNow Authentication Token / Bearer Token | `Bearer secret_token_xyz123` |
| `GRAPH_TENANT_ID` | Azure / Entra ID Tenant ID for Intune Dev | `00000000-0000-0000-0000-000000000000` |
| `GRAPH_CLIENT_ID` | App Registration Client ID (Intune Publisher) | `11111111-1111-1111-1111-111111111111` |
| `GRAPH_CLIENT_SECRET` | App Registration Client Secret | `SecretValue~xyz` |

---

## 🔄 Step 2: ServiceNow Outbound Setup (ServiceNow Dev $\rightarrow$ GitHub Dev)

ServiceNow me jab `SCTASK` approve hota hai, to ek **Business Rule** run hota hai jo GitHub Dispatch API ko call karta hai:

### **ServiceNow Business Rule Script (After Update / Approval):**
```javascript
(function executeRule(current, previous /*null when async*/) {
    if (current.approval == 'approved' && previous.approval != 'approved') {
        
        var request = new sn_ws.RESTMessageV2();
        request.setEndpoint('https://api.github.com/repos/YOUR_ORG/intune-application-packaging-dev/dispatches');
        request.setHttpMethod('POST');
        
        request.setRequestHeader('Authorization', 'token ' + gs.getProperty('github.pat.token'));
        request.setRequestHeader('Accept', 'application/vnd.github.v3+json');
        request.setRequestHeader('Content-Type', 'application/json');
        
        var payload = {
            "event_type": "build-app-package",
            "client_payload": {
                "sctask_id": current.number.toString(),
                "app_name": current.variables.app_name.toString().toLowerCase(),
                "app_version": current.variables.app_version.toString(),
                "app_track_id": current.variables.app_track_id.toString()
            }
        };
        
        request.setRequestBody(JSON.stringify(payload));
        var response = request.execute();
        gs.info("GitHub Dispatch Sent. HTTP Status: " + response.getStatusCode());
    }
})(current, previous);
```

---

## 🔍 Step 3: Line-by-Line Workflow Breakdown (`package-app.yml`)

`package-app.yml` file ke har block aur keyword ka detail explanation:

* **`on: repository_dispatch`**: ServiceNow se automatic HTTP POST API event aane par workflow launch karta hai.
* **`on: workflow_dispatch`**: GitHub website UI par manual test run button enable karta hai.
* **`runs-on: [self-hosted, Windows]`**: Packaging tool (`IntuneWinAppUtil.exe`) ke liye Windows runner select karta hai.
* **`uses: actions/checkout@v4`**: Repository ka exact source code checkout/clone karta hai.
* **`if: success()`**: Sirf tabhi execute hoga jab upar ke saare steps PASS hue ho (ServiceNow Ko Auto-close bhejega).
* **`if: failure()`**: Tab execute hoga jab koi step FAIL ho (ServiceNow ticket ko On Hold rakhega).
* **`if: always()`**: Build logs aur `.intunewin` evidence artifacts ko hamesha GitHub Actions me save karke rakhta hai.

---

## 📜 Step 4: Application Manifest Deep-Dive (`notepadplusplus.json`)

Har application ki configuration `manifests/` folder me ek JSON file me hoti hai:

```json
{
  "appName": "notepadplusplus",
  "displayName": "Notepad++ (x64)",
  "version": "8.6.5",
  "appTrackId": "APP-NPP-001",
  "setupFile": "npp.8.6.5.Installer.x64.exe",
  "downloadUrl": "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.5/npp.8.6.5.Installer.x64.exe",
  "expectedSha256": "C5C4D81B85D3B8B82B5B0F1C1D82490A093D89E4647D0E6983A899C5E5D8F0A2",
  "installCommand": "npp.8.6.5.Installer.x64.exe /S",
  "uninstallCommand": "\"%ProgramFiles%\\Notepad++\\uninstall.exe\" /S"
}
```

---

## 🚀 Step 5: Testing & Execution Guide

### **Method A: ServiceNow End-to-End Trigger Test**
1. ServiceNow Dev me Naya Catalog Request raise karein (`App: notepadplusplus`, `Version: 8.6.5`).
2. `SCTASK` ko **Approve** karein.
3. GitHub Actions automatic package build karke `SCTASK` ko **Closed Complete** kar dega.

### **Method B: GitHub Actions Manual UI Trigger Test**
1. GitHub Repository me **Actions** tab par jayein.
2. Select **Intune Application Packaging & ServiceNow Automation Pipeline**.
3. Click **Run workflow** $\rightarrow$ Enter `sctask_id`, `app_name`, `app_version` $\rightarrow$ Run.

---
