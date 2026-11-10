# Hướng Dẫn Chi Tiết Giai Đoạn 5: Giám Sát Endpoint Windows 10 (Wazuh Agent + Sysmon + Active Response)

Tài liệu này hướng dẫn từng bước (Step-by-step) mở rộng phòng lab từ giám sát **Web/WAF** sang giám sát **Endpoint**: bổ sung **VM 4 – Windows 10 Client (`192.168.1.40`)** gửi Windows Event Log và **Sysmon** về **Wazuh SIEM (VM 3 `192.168.1.30`)**, xây dựng bộ luật phát hiện tùy chỉnh theo **MITRE ATT&CK**, và tự động chặn IP tấn công brute-force bằng **Windows Defender Firewall** thông qua **Active Response**.

---

## 🗺️ 1. MÔ HÌNH GIÁM SÁT ENDPOINT (EDR-LIKE PIPELINE)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ VM 1: ATTACKER HOST (Kali Linux - 192.168.1.10)                        │
│   [test-windows-attacks.sh]                                             │
│   └── SMB Brute-force (smbclient, 15 lần đăng nhập sai) -> TCP 445      │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ VM 4: WINDOWS 10 CLIENT (192.168.1.40)                                  │
│                                                                         │
│   1. Windows Defender Firewall: Rule "WazuhAR-Block-<IP>" (khi bị chặn) │
│   2. Nguồn log:                                                         │
│      ├── Security (4625, 4720, 4732, 1102)  <- Advanced Audit Policy    │
│      ├── Microsoft-Windows-Sysmon/Operational (Event 1: Process Create) │
│      ├── Microsoft-Windows-PowerShell/Operational (4104 Script Block)   │
│      └── Microsoft-Windows-Windows Defender/Operational                 │
│   3. Wazuh Agent 4.8.2 (WazuhSvc) - group "windows"                     │
│   4. Active Response: active-response\bin\win-firewall-drop.cmd         │
│   [simulate-windows-events.ps1] - sinh sự kiện hậu khai thác an toàn    │
└────────────────────────────────────▲────────────────────────────────────┘
                                     │ Event Log (TCP 1514) / Lệnh AR add|delete
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ VM 3: WAZUH SIEM (192.168.1.30)                                         │
│   ├── /var/ossec/etc/shared/windows/agent.conf (cấu hình tập trung)     │
│   ├── /var/ossec/etc/rules/windows_rules.xml (Rule 100200 - 100213)     │
│   └── Active Response: Rule 100201 -> win-firewall-drop (timeout 600s)  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🎯 2. MỤC TIÊU CỦA GIAI ĐOẠN 5

1. Bổ sung một endpoint Windows 10 vào hạ tầng SIEM, đăng ký vào **agent group `windows`** để quản lý cấu hình tập trung từ Manager.
2. Thu thập log chuyên sâu: Security Event Log (Advanced Audit Policy), **Sysmon** và **PowerShell Script Block Logging**.
3. Xây dựng bộ luật tùy chỉnh `windows_rules.xml` (ID `100200`–`100213`) phát hiện Brute-force, Persistence, Privilege Escalation, Execution, Discovery, Credential Access, Defense Evasion.
4. Tự động cô lập IP tấn công brute-force bằng Active Response `win-firewall-drop` (Windows Defender Firewall).

---

## 📁 3. CÁC FILE LIÊN QUAN TRONG REPO

```plaintext
vm3-wazuh-manager/
├── custom-rules/windows_rules.xml         # Luật tùy chỉnh 100200 - 100213 (copy lên VM 3)
└── shared/windows/agent.conf              # Cấu hình tập trung cho group "windows" (copy lên VM 3)
vm4-windows-client/
└── active-response/
    ├── win-firewall-drop.cmd              # Wrapper được Wazuh Agent gọi (chuyển stdin sang PowerShell 64-bit)
    └── win-firewall-drop.ps1              # Thêm/xóa rule chặn IP trong Windows Defender Firewall
scripts/
├── setup-vm4-windows-agent.ps1            # Cài Agent + Sysmon + Audit Policy + Firewall lab + AR (chạy trên VM 4)
├── simulate-windows-events.ps1            # Sinh sự kiện kiểm thử an toàn (chạy trên VM 4)
└── test-windows-attacks.sh                # SMB brute-force + kiểm tra chặn IP (chạy trên VM 1)
```

### Bảng luật phát hiện (`windows_rules.xml`):

| Rule ID | Level | Nguồn log | Điều kiện kích hoạt | MITRE ATT&CK |
| :---: | :---: | :--- | :--- | :--- |
| **`100200`** | 5 | Security | Đăng nhập thất bại (Event `4625`) | T1110 |
| **`100201`** | **12** | Security | Cùng 1 IP đăng nhập sai $\ge 8$ lần trong 60 giây → **Kích hoạt Active Response** | T1110.001 |
| **`100202`** | 8 | Security | Tạo tài khoản cục bộ mới (Event `4720`) | T1136.001 |
| **`100203`** | 12 | Security | Thêm thành viên vào nhóm Administrators (Event `4732`, SID `S-1-5-32-544`) | T1098 |
| **`100204`** | 13 | Security | Xóa Security Event Log (Event `1102`) | T1070.001 |
| **`100210`** | 12 | Sysmon 1 | `powershell.exe` chạy với `-EncodedCommand` / `-enc` / `-e` | T1059.001, T1027 |
| **`100211`** | 8 | Sysmon 1 | `whoami /priv\|/all\|/groups`, `net user`, `net localgroup` | T1033, T1087.001 |
| **`100212`** | **14** | Sysmon 1 | Command line chứa `mimikatz`, `sekurlsa::`, `lsadump::`, `procdump ... lsass` | T1003.001 |
| **`100213`** | 10 | PowerShell 4104 | Script block chứa `Invoke-Expression`/`IEX`, `DownloadString`, `FromBase64String` | T1059.001 |

> [!NOTE]
> Các luật bám vào group có sẵn của Wazuh (`authentication_failed`, `windows`, `sysmon_event1`) bằng `<if_group>`. Group bao ngoài của file là `custom_windows` — **không** dùng `windows` (tránh luật tự làm cha của chính nó) và **không** dùng `web_attack` (tránh bị Rule tương quan `100110` của ModSecurity đếm nhầm).

---

## 🛠️ 4. BƯỚC 1: CHUẨN BỊ MÁY ẢO VM 4

Tạo máy ảo Windows 10 và cấu hình IP tĩnh `192.168.1.40` theo hướng dẫn tại [**`docs/phase0-vmware-setup.md`**](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/docs/phase0-vmware-setup.md) (mục **4.4** và **5.5**).

Kiểm tra nhanh trên VM 4 (PowerShell):
```powershell
Test-NetConnection 192.168.1.30 -Port 1514   # TcpTestSucceeded : True
Test-NetConnection 192.168.1.30 -Port 1515   # TcpTestSucceeded : True (cổng đăng ký Agent)
Get-Date                                     # Đồng bộ giờ với VM 3 (lệch < 5 phút)
```

---

## 🧠 5. BƯỚC 2: CHUẨN BỊ WAZUH MANAGER (VM 3 `192.168.1.30`)

> [!IMPORTANT]
> Phải tạo **agent group `windows`** trên Manager **trước** khi cài Agent trên VM 4. Nếu group chưa tồn tại, quá trình đăng ký (enrollment) với tham số `WAZUH_AGENT_GROUP=windows` sẽ bị Manager từ chối (`Invalid group`).

Đăng nhập VM 3 (`ssh admin@192.168.1.30`) và đồng bộ repo:
```bash
cd ~/wazuh-modsec-siem-lab
git pull
```

### 5.1. Tạo agent group và nạp cấu hình tập trung:
```bash
# Tạo group "windows"
sudo /var/ossec/bin/agent_groups -a -g windows -q

# Ghi đè agent.conf của group
sudo cp vm3-wazuh-manager/shared/windows/agent.conf /var/ossec/etc/shared/windows/agent.conf
sudo chown wazuh:wazuh /var/ossec/etc/shared/windows/agent.conf
sudo chmod 660 /var/ossec/etc/shared/windows/agent.conf

# Kiểm tra cú pháp agent.conf
sudo /var/ossec/bin/verify-agent-conf
```

### 5.2. Nạp bộ luật Windows:
```bash
sudo cp vm3-wazuh-manager/custom-rules/windows_rules.xml /var/ossec/etc/rules/
sudo chown wazuh:wazuh /var/ossec/etc/rules/windows_rules.xml
sudo chmod 660 /var/ossec/etc/rules/windows_rules.xml
```

### 5.3. Khai báo Command & Active Response cho Windows:
Mở `/var/ossec/etc/ossec.conf`, chèn **bên cạnh** khối `docker-firewall-drop` đã có từ Giai đoạn 3 (trước thẻ đóng `</ossec_config>`):

```xml
  <!-- Active Response cho VM 4 (Windows): chặn IP brute-force bằng Windows Defender Firewall -->
  <command>
    <name>win-firewall-drop</name>
    <executable>win-firewall-drop.cmd</executable>
    <timeout_allowed>yes</timeout_allowed>
  </command>

  <active-response>
    <disabled>no</disabled>
    <command>win-firewall-drop</command>
    <location>local</location>
    <rules_id>100201</rules_id>
    <timeout>600</timeout> <!-- Tự động gỡ chặn sau 10 phút -->
  </active-response>
```

> [!NOTE]
> Không dùng lệnh `netsh` có sẵn của Wazuh vì nó đọc IP từ trường `data.srcip`, trong khi sự kiện Windows chứa IP nguồn tại `data.win.eventdata.ipAddress`. Script `win-firewall-drop.ps1` đọc đúng trường này.

### 5.4. Kiểm tra cú pháp và khởi động lại Manager:
```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo systemctl restart wazuh-manager
```

---

## 🤖 6. BƯỚC 3: CÀI ĐẶT WAZUH AGENT, SYSMON & ACTIVE RESPONSE TRÊN VM 4

### 6.1. Đưa mã nguồn repo về VM 4:
Mở **PowerShell (Run as Administrator)**:

* **Cách 1 – Git (khuyên dùng):**
  ```powershell
  winget install --id Git.Git -e --source winget
  # Mở lại PowerShell (Admin) để nhận PATH mới
  cd C:\
  git clone https://github.com/nace1504/wazuh-modsec-siem-lab.git
  cd C:\wazuh-modsec-siem-lab
  ```
* **Cách 2 – Tải ZIP:** Tải `Code > Download ZIP` từ GitHub, giải nén vào `C:\wazuh-modsec-siem-lab`, sau đó gỡ cờ "tải từ Internet":
  ```powershell
  cd C:\wazuh-modsec-siem-lab
  Get-ChildItem -Recurse | Unblock-File
  ```

### 6.2. Chạy script cài đặt tự động:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-vm4-windows-agent.ps1 -ManagerIP 192.168.1.30 -AgentName vm4-win-client
```

*Script sẽ tự động:*
1. Tải và cài **Wazuh Agent `4.8.2-1`** (MSI, trùng phiên bản Manager) với `WAZUH_MANAGER`, `WAZUH_AGENT_NAME`, `WAZUH_AGENT_GROUP=windows`.
2. Tải và cài **Sysmon64** với cấu hình cộng đồng **SwiftOnSecurity** (nếu đã cài thì cập nhật cấu hình).
3. Bật **Advanced Audit Policy** (Logon, Account Lockout, User Account Management, Security Group Management, Process Creation) bằng GUID — không phụ thuộc ngôn ngữ Windows.
4. Bật **PowerShell Script Block Logging** (Event 4104).
5. Mở tường lửa cho ICMP, SMB `445`, RDP `3389` **chỉ từ dải `192.168.1.0/24`** (phục vụ kịch bản tấn công) và bật Remote Desktop.
6. Cài script Active Response `win-firewall-drop.cmd/.ps1` vào `C:\Program Files (x86)\ossec-agent\active-response\bin\`.
7. Khởi động dịch vụ `WazuhSvc` và kiểm tra dòng `Connected to the server` trong `ossec.log`.

### 6.3. Chốt chặn kiểm thử 5A (Checkpoint – Kết nối Agent):
**Trên VM 3:**
```bash
sudo /var/ossec/bin/agent_control -l
# Kỳ vọng: ID: 00X, Name: vm4-win-client, IP: any, Active

sudo /var/ossec/bin/agent_groups -l -g windows
# Kỳ vọng: vm4-win-client nằm trong group windows
```

**Trên VM 4:**
```powershell
Get-Service WazuhSvc, Sysmon64                     # Cả hai: Running
Get-Content 'C:\Program Files (x86)\ossec-agent\ossec.log' -Tail 20
# Kỳ vọng: "Connected to the server ([192.168.1.30]:1514/tcp)"
#          "Analyzing event log: 'Microsoft-Windows-Sysmon/Operational'"
Get-WinEvent -LogName 'Microsoft-Windows-Sysmon/Operational' -MaxEvents 3
```

> 💡 Nếu `ossec.log` chưa có dòng `Analyzing event log: 'Microsoft-Windows-Sysmon/Operational'`, đợi 1–2 phút để Agent nhận `agent.conf` từ group và tự khởi động lại, hoặc chạy `Restart-Service WazuhSvc`.

---

## 🚀 7. BƯỚC 4: KIỂM THỬ PHÁT HIỆN & PHẢN ỨNG

Mở sẵn một terminal trên **VM 3** để theo dõi cảnh báo thời gian thực:
```bash
sudo tail -f /var/ossec/logs/alerts/alerts.json | jq -c 'select(.agent.name=="vm4-win-client") | {id: .rule.id, level: .rule.level, desc: .rule.description}'
```

### 7.1. Kịch bản A – Hậu khai thác trên Endpoint (chạy trên VM 4):
```powershell
cd C:\wazuh-modsec-siem-lab
powershell -ExecutionPolicy Bypass -File .\scripts\simulate-windows-events.ps1
# Thêm -ClearSecurityLog để kiểm thử Rule 100204 (XÓA Security log cục bộ!)
```

Script chỉ sinh sự kiện **an toàn** (không chạy mã độc thật):

| Bước | Hành động mô phỏng | Rule kỳ vọng |
| :--- | :--- | :--- |
| 1 | `net user lab-backdoor <pass> /add` | `100202` + `100211` |
| 2 | `Add-LocalGroupMember -SID S-1-5-32-544` | `100203` |
| 3 | `whoami /priv`, `net localgroup` | `100211` |
| 4 | `cmd /c powershell -EncodedCommand ...` (nội dung: `Invoke-Expression 'Get-Date'`) | `100210` + `100213` |
| 5 | `cmd /c echo sekurlsa::logonpasswords > nul` | `100212` |
| 6 | (Tùy chọn) `wevtutil cl Security` | `100204` |
| 7 | Xóa tài khoản `lab-backdoor` (dọn dẹp) | — |

### 7.2. Kịch bản B – SMB Brute-force & Active Response (chạy trên VM 1 Kali):
```bash
cd ~/wazuh-modsec-siem-lab
git pull
bash scripts/test-windows-attacks.sh 192.168.1.40
```

#### Kết quả kỳ vọng trên terminal Kali Linux:
```text
--- [Phase 1: Reachability Baseline] ---
[*] Checking SMB port 445 on 192.168.1.40 ... [PASS] Port 445 open

--- [Phase 2: SMB Password Brute-force (Event 4625 -> Rule 100200)] ---
[*] Sending 15 failed logons as 'lab-bruteforce' (Rule 100201 threshold >= 8 in 60s) .........
[✓] Connection stalled at attempt #10 -> Active Response already kicked in

--- [Phase 3: Automated Verification of IP Blocking] ---
[*] Re-checking SMB port 445 from Attacker host ... [PASS] Attacker IP is successfully BLOCKED by Windows Firewall! (Connection timed out)
[✓] Windows Endpoint Detection & Response Test PASSED
```

---

## 🔍 8. KIỂM CHỨNG TRÊN TỪNG THÀNH PHẦN

### 8.1. Trên VM 4 (Windows 10):
```powershell
# Rule tường lửa do Active Response tạo
netsh advfirewall firewall show rule name="WazuhAR-Block-192.168.1.10"

# Nhật ký Active Response
Get-Content 'C:\Program Files (x86)\ossec-agent\active-response\active-responses.log' -Tail 10
# Kỳ vọng: "... win-firewall-drop: Successfully BLOCKED attack IP: 192.168.1.10 ..."

# Sự kiện đăng nhập thất bại gốc
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625} -MaxEvents 5 | Format-List TimeCreated, Message
```

### 8.2. Trên Wazuh Dashboard (`https://192.168.1.30`):
1. **Threat Hunting / Security events** → chọn agent `vm4-win-client`.
2. Lọc theo các truy vấn:
   * `rule.groups: "custom_windows"` – toàn bộ cảnh báo tùy chỉnh của Windows.
   * `rule.id: (100200 OR 100201 OR 100202 OR 100203 OR 100204 OR 100210 OR 100211 OR 100212 OR 100213)`
   * `data.win.eventdata.ipAddress: "192.168.1.10"` – truy vết IP tấn công.
3. Mở module **MITRE ATT&CK** → quan sát các kỹ thuật `T1110`, `T1136`, `T1098`, `T1059.001`, `T1003.001` xuất hiện trên ma trận.
4. Mở chi tiết một cảnh báo Sysmon → kiểm tra các trường `data.win.eventdata.commandLine`, `parentImage`, `user` (phục vụ điều tra chuỗi tiến trình).

---

## 🔓 9. QUY TRÌNH GỠ KHÓA IP (UNBLOCK WORKFLOW)

### Cách 1: Gỡ khóa thủ công ngay lập tức (PowerShell Admin trên VM 4):
```powershell
& 'C:\Program Files (x86)\ossec-agent\active-response\bin\win-firewall-drop.cmd' delete 192.168.1.10
```
Hoặc gỡ trực tiếp bằng `netsh`:
```powershell
netsh advfirewall firewall delete rule name="WazuhAR-Block-192.168.1.10"
```

### Cách 2: Chờ Timeout tự động:
Với `<timeout>600</timeout>`, sau 10 phút Wazuh Agent tự gọi lại `win-firewall-drop` với lệnh `delete`.

---

## 🧯 10. BẢNG XỬ LÝ SỰ CỐ (TROUBLESHOOTING)

| Hiện tượng | Nguyên nhân | Cách khắc phục |
| :--- | :--- | :--- |
| `msiexec` thành công nhưng Agent không xuất hiện trên VM 3; `ossec.log` báo `Invalid group`. | Chưa tạo group `windows` trên Manager. | Chạy lại mục **5.1** trên VM 3, sau đó `Restart-Service WazuhSvc` trên VM 4. |
| `ossec.log` báo `Agent version must be lower or equal to manager version`. | Cài sai phiên bản Agent. | Gỡ Agent trong *Apps & features*, chạy lại script với `-WazuhVersion 4.8.2-1`. |
| Có alert Windows mặc định (60xxx) nhưng không có Rule `100200`. | Luật gốc của sự kiện 4625 không thuộc group `authentication_failed` trên phiên bản đang chạy. | Bật `<logall_json>yes</logall_json>` hoặc xem `rule.id` của alert 4625 trên Dashboard, đổi `<if_group>authentication_failed</if_group>` thành `<if_sid>ID_đó</if_sid>`. |
| Lệnh encoded/whoami bị gắn Rule built-in `92xxx` thay vì `100210`/`100211`. | Luật Sysmon có sẵn của Wazuh khớp trước (cũng là phát hiện hợp lệ). | Chấp nhận (vẫn phát hiện), hoặc thêm `<if_sid>92xxx</if_sid>` tương ứng vào luật tùy chỉnh để ghi đè. |
| Rule `100201` kích hoạt nhưng IP không bị chặn; `active-responses.log` báo `Missing or invalid IP`. | Sự kiện 4625 không có `ipAddress` (ví dụ đăng nhập cục bộ hoặc RDP có NLA). | Dùng kịch bản SMB (`test-windows-attacks.sh`), không dùng RDP brute-force để demo AR. |
| `active-responses.log` không có dòng nào sau khi Rule `100201` kích hoạt. | Chưa khai báo `<command>`/`<active-response>` trên Manager hoặc thiếu file `.cmd` trên VM 4. | Kiểm tra mục **5.3**, kiểm tra `Test-Path 'C:\Program Files (x86)\ossec-agent\active-response\bin\win-firewall-drop.cmd'`. |
| Kali không thể kết nối cổng 445 ngay từ Phase 1. | IP Kali đang bị chặn từ lần chạy trước, hoặc thiếu rule `Lab-Allow-SMB-445`. | Gỡ chặn theo mục **9**; chạy lại script setup ở mục **6.2**. |
| Script `.ps1` báo lỗi `cannot be loaded because running scripts is disabled`. | Execution Policy mặc định của Windows 10. | Luôn chạy qua `powershell -ExecutionPolicy Bypass -File ...`. |

---

## ✅ 11. BẢNG CHECKLIST NGHIỆM THU GIAI ĐOẠN 5

- [ ] **5.1** VM 4 Windows 10 có IP tĩnh `192.168.1.40`, ping thông VM 3 và kết nối được cổng `1514`/`1515`.
- [ ] **5.2** Group `windows` đã tạo trên VM 3, `agent.conf` hợp lệ (`verify-agent-conf`).
- [ ] **5.3** `windows_rules.xml` đã nạp và `wazuh-analysisd -t` không lỗi.
- [ ] **5.4** Khối `<command>`/`<active-response>` `win-firewall-drop` (Rule `100201`) đã khai báo trên VM 3.
- [ ] **5.5** Agent `vm4-win-client` ở trạng thái **Active** và thuộc group `windows`.
- [ ] **5.6** Sysmon64 đang chạy và Agent đọc kênh `Microsoft-Windows-Sysmon/Operational`.
- [ ] **5.7** `simulate-windows-events.ps1` sinh đủ cảnh báo `100202`, `100203`, `100210`, `100211`, `100212`, `100213`.
- [ ] **5.8** `test-windows-attacks.sh` kích hoạt Rule `100201` (Level 12) và VM 4 tự sinh rule `WazuhAR-Block-192.168.1.10`.
- [ ] **5.9** Kali bị cô lập khỏi VM 4 (cổng 445 timeout) và gỡ chặn thành công bằng `win-firewall-drop.cmd delete`.
- [ ] **5.10** Dashboard hiển thị cảnh báo của `vm4-win-client` trên module MITRE ATT&CK.

---

## 📤 12. XUẤT CẢNH BÁO DEMO CHO AI AGENT XỬ LÝ CẢNH BÁO (ALERT TRIAGE)

Script [`scripts/export-demo-alerts.sh`](../scripts/export-demo-alerts.sh) (chạy trên **VM 3**) xuất toàn bộ cảnh báo trong khung giờ demo thành bộ dữ liệu có nhãn, dùng làm đầu vào / tập đánh giá cho AI agent:

```bash
cd ~/wazuh-modsec-siem-lab && git pull

# Xác định giờ cảnh báo đầu/cuối của buổi demo
sudo jq -r 'select(.agent.name=="vm4-win-client" and (.rule.id|tonumber)>=100200 and (.rule.id|tonumber)<100300) | .timestamp' /var/ossec/logs/alerts/alerts.json | sed -n '1p;$p'

# Xuất (nới rộng vài phút mỗi đầu); mặc định lấy vm4-win-client + vm2-web-target, level >= 3
sudo bash scripts/export-demo-alerts.sh 2026-11-11T14:40:00 2026-11-11T15:30:00
```

Kết quả: thư mục `~/demo-alerts-<thời_gian>/` và file nén `~/demo-alerts-<thời_gian>.tar.gz` gồm:

| File | Nội dung |
| :--- | :--- |
| `alerts.jsonl` | Mỗi dòng là 1 cảnh báo Wazuh gốc (đủ `rule`, `mitre`, `agent`, `data.win.*`, `data.transaction.*`, `full_log`), sắp xếp theo thời gian, đã bổ sung trường **`ground_truth`** (`label`, `scenario`, `reason`) |
| `summary.md` | Mô tả môi trường lab, định nghĩa nhãn, thống kê theo nhãn và theo rule, giải thích các trường quan trọng |

* **Gắn nhãn tự động:** `true_positive` cho cảnh báo từ IP attacker (`web_attack_waf`, `smb_bruteforce`, `attacker_ip_activity`) và cảnh báo mô phỏng hậu khai thác (`post_exploitation_simulation`); còn lại là `benign` / `background`.
* **Che dữ liệu nhạy cảm:** mật khẩu trong lệnh `net user <tên> <mật_khẩu> /add` được thay bằng `***REDACTED***`.
* **Tùy chỉnh** qua biến môi trường: `AGENTS="vm4-win-client"`, `MIN_LEVEL=5`, `ATTACKER_IP=...`.

Tải file nén về máy thật (PowerShell trên Windows host):
```powershell
scp ubuntu@192.168.1.30:~/demo-alerts-<thời_gian>.tar.gz .
```

---

## 🎯 KẾT LUẬN GIAI ĐOẠN 5
Hệ thống SIEM đã được mở rộng từ giám sát tầng ứng dụng Web sang giám sát tầng Endpoint, hoàn thiện mô hình phòng thủ nhiều lớp:
$$\text{Attack (Kali)} \longrightarrow \text{Endpoint Telemetry (Event Log + Sysmon)} \longrightarrow \text{Correlate (Wazuh Rules)} \longrightarrow \text{Active Response (Windows Firewall)}$$

👉 Tiếp theo: **Giai đoạn 6 – Sẵn sàng triển khai Cloud** trong [**`docs/deployment-plan.md`**](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/docs/deployment-plan.md).
