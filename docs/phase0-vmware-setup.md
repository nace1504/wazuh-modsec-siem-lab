# Hướng Dẫn Chi Tiết Giai Đoạn 0: Thiết Lập Mạng Ảo & Khởi Tạo Máy Ảo Trên VMware

Tài liệu này là cẩm nang hướng dẫn từng bước (Step-by-step click-by-click) dành cho kỹ sư triển khai phòng lab **Wazuh ModSecurity SIEM** trên phần mềm **VMware Workstation Pro / Player**.

---

## 🗺️ 1. SƠ ĐỒ TOPO MẠNG PHÒNG LAB

```
                 [Internet / WAN]
                        │
                  (NAT Engine)
          VMware Virtual Switch: VMnet8
           Subnet: 192.168.1.0/24
           Gateway: 192.168.1.2
                        │
      ┌─────────────────┼─────────────────┐
      │                 │                 │
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ VM 1: ATTACK │ │ VM 2: TARGET │ │ VM 3: SIEM   │
│ Kali Linux   │ │ Ubuntu 22.04 │ │ Ubuntu 22.04 │
│ 192.168.1.10 │ │ 192.168.1.20 │ │ 192.168.1.30 │
└──────────────┘ └──────────────┘ └──────────────┘
```

---

## 📋 2. BẢNG DỰ TOÁN TÀI NGUYÊN & MAPPING FILE NGUỒN CỐ ĐỊNH (CHUẨN UBUNTU 22.04 LTS)

Hệ thống được thống nhất chuẩn hóa toàn diện trên nền tảng **Ubuntu Server 22.04 LTS** cho toàn bộ máy chủ server:
1. `kali-linux-2024.4-vmware-amd64.7z` (Bản máy ảo VMware đóng gói sẵn - Pre-built Image cho VM 1 Attacker).
2. Thư mục `iso ubuntu 22.04.5` (File ISO Ubuntu Server 22.04.5 LTS dùng chung cho cả VM 2 và VM 3).

### Bảng phân bổ cấu hình chi tiết cho 3 máy ảo:

| Máy ảo | Vai trò & Nguồn cài đặt | vCPU | RAM | Ổ cứng SSD | Network Adapter | Địa chỉ IP Tĩnh |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **VM 1** | **Attacker**<br>• Dùng: `kali-linux-2024.4-vmware-amd64.7z`<br>*(Giải nén mở trực tiếp .vmx, không cần cài)* | 2 Cores | 2 GB - 4 GB | ~25 GB (Có sẵn) | Custom: `VMnet8 (NAT)` | `192.168.1.10/24`<br>User: `kali`<br>Pass: `kali` |
| **VM 2** | **Web Target & WAF**<br>• Dùng: ISO trong `iso ubuntu 22.04.5`<br>*(Ubuntu Server 22.04.5 LTS)* | 2 Cores | 4 GB | 30 GB (Thin) | Custom: `VMnet8 (NAT)` | `192.168.1.20/24`<br>User: `admin` |
| **VM 3** | **Wazuh AIO SIEM**<br>• Dùng: ISO trong `iso ubuntu 22.04.5`<br>*(Ubuntu Server 22.04.5 LTS)* | **4 Cores** | **8 GB** | **50 GB (Thin)** | Custom: `VMnet8 (NAT)` | `192.168.1.30/24`<br>User: `admin` |
| **TỔNG**| **Yêu cầu máy Host (Windows/Linux)**| **$\ge$ 8 Threads** | **$\ge$ 16 GB** | **$\ge$ 110 GB** | | |

> [!NOTE]
> * **Lợi thế khi đồng bộ Ubuntu 22.04.5 LTS cho cả VM 2 và VM 3:**
>   1. **Tương thích tuyệt đối với Wazuh SIEM:** Toàn bộ script cài đặt tự động `wazuh-install.sh` của Wazuh Manager, Indexer (OpenSearch 2.x) và Wazuh Dashboard đạt độ ổn định cao nhất trên Ubuntu 22.04 LTS (Jammy Jellyfish).
>   2. **Đồng bộ môi trường DevOps:** Cùng phiên bản Linux Kernel, thư viện hệ thống và cấu hình Netplan giống hệt nhau, loại bỏ hoàn toàn các lỗi xung đột phiên bản.
>   3. **Tiết kiệm tài nguyên:** Cả 2 máy chủ ảo VM 2 và VM 3 đều dùng chung một file ISO từ thư mục `iso ubuntu 22.04.5`.

---

## ⚙️ 3. BƯỚC 1: CẤU HÌNH VMWARE VIRTUAL NETWORK EDITOR

1. **Khởi động quyền Admin:** Nhấp chuột phải vào biểu tượng **VMware Workstation Pro** trên màn hình Desktop -> Chọn **Run as administrator**.
2. **Mở bộ quản lý mạng:** Trên thanh menu chọn **Edit** $\rightarrow$ **Virtual Network Editor...**.
3. **Cấp quyền quản trị:** Nhấn nút **Change Settings** (nằm ở góc dưới cùng bên phải cửa sổ).
4. **Cấu hình card VMnet8 (NAT):**
   * Trong danh sách mạng, chọn **VMnet8**.
   * Đảm bảo chọn kiểu: **NAT (shared host's IP address with VMs)**.
   * Tích chọn: `Connect a host virtual adapter to this network` (để máy thật Windows có thể SSH vào các VM).
   * Tích chọn: `Use local DHCP service to distribute IP address to VMs`.
   * **Subnet IP:** `192.168.1.0`
   * **Subnet mask:** `255.255.255.0`
5. **Cấu hình Gateway (NAT Settings):**
   * Nhấn nút **NAT Settings...**.
   * Tại ô **Gateway IP**, điền chính xác: `192.168.1.2`.
   * Nhấn **OK**.
6. **Cấu hình dải cấp phát DHCP (DHCP Settings):**
   * Nhấn nút **DHCP Settings...**.
   * **Start IP address:** `192.168.1.100`
   * **End IP address:** `192.168.1.200`
   * *(Lưu ý: Dải từ `192.168.1.3` đến `192.168.1.99` sẽ được giữ trống hoàn toàn để cấp IP tĩnh cho 3 VM mà không bị DHCP tranh chấp).*
   * Nhấn **OK**.
7. Nhấn **Apply** $\rightarrow$ Nhấn **OK** để hoàn tất cấu hình switch ảo.

---

## 💻 4. BƯỚC 2: KHỞI TẠO 3 MÁY ẢO TRÊN VMWARE

### 4.1. Khởi tạo VM 1: Attacker (Sử dụng `kali-linux-2024.4-vmware-amd64.7z`)
> 💡 **Lợi ích:** Đây là máy ảo VMware dựng sẵn chính thức từ trang chủ Kali. Bạn **không cần cài đặt qua file ISO**, tiết kiệm 90% thời gian!

1. **Giải nén máy ảo:**
   * Nhấp chuột phải vào file `kali-linux-2024.4-vmware-amd64.7z` $\rightarrow$ Chọn **7-Zip** (hoặc WinRAR) $\rightarrow$ **Extract to "kali-linux-2024.4-vmware-amd64"**.
   * Di chuyển thư mục vừa giải nén đến phân vùng ổ SSD mà bạn muốn lưu trữ máy ảo.
2. **Mở máy ảo trên VMware Workstation:**
   * Trên VMware Workstation, chọn **File** $\rightarrow$ **Open...** (hoặc phím tắt `Ctrl + O`).
   * Điều hướng vào thư mục vừa giải nén, chọn file có đuôi: **`kali-linux-2024.4-vmware-amd64.vmx`** $\rightarrow$ Nhấn **Open**.
3. **Cấu hình phần cứng & Card mạng:**
   * Trong giao diện máy ảo `kali-linux-2024.4-vmware-amd64`, nhấn **Edit virtual machine settings**.
   * Chọn mục **Memory:** Điều chỉnh về `2048 MB` (hoặc `4096 MB` nếu máy Host có $\ge 16$GB RAM).
   * Chọn mục **Processors:** Đặt `2 Cores`.
   * Chọn mục **Network Adapter:** Tích chọn **Custom: Specific virtual network** $\rightarrow$ Chọn **`VMnet8 (NAT)`**.
   * Nhấn **OK**.
4. **Khởi động và xác nhận:**
   * Nhấn **Power on this virtual machine**.
   * Nếu VMware hiện bảng thông báo hỏi *"Did you move it or copy it?"* $\rightarrow$ **Bắt buộc chọn: "I Copied It"** (để VMware tự tạo MAC address mới, tránh xung đột mạng).
   * **Thông tin đăng nhập mặc định:**
     * Username: `kali`
     * Password: `kali`

---

### 4.2. Khởi tạo VM 2: Web Target & WAF (Sử dụng ISO trong thư mục `iso ubuntu 22.04.5`)
1. Chọn **File** $\rightarrow$ **New Virtual Machine...** $\rightarrow$ Chọn **Custom (advanced)** $\rightarrow$ **Next**.
2. Hardware compatibility: Mặc định (Workstation 17.x / 16.x) $\rightarrow$ **Next**.
3. **Guest OS Installation:** Chọn *Installer disc image file (iso)* $\rightarrow$ Browse vào thư mục **`iso ubuntu 22.04.5`** $\rightarrow$ Chọn file ISO bên trong $\rightarrow$ Nhấn **Next**.
4. **Guest operating system:** Chọn **Linux**, Version: **Ubuntu 64-bit** $\rightarrow$ **Next**.
5. **Virtual machine name:** Đặt tên `VM2-Web-Target-WAF` $\rightarrow$ Chọn thư mục lưu trữ máy ảo trên SSD $\rightarrow$ **Next**.
6. **Processor Configuration:** 
   * Processors: `1`, Cores per processor: `2` (Tổng 2 Cores) $\rightarrow$ **Next**.
7. **Memory:** Điền `4096 MB` (4 GB RAM) $\rightarrow$ **Next**.
8. **Network Connection:** Chọn **Use custom virtual network** $\rightarrow$ Chọn **`VMnet8 (NAT)`** $\rightarrow$ **Next**.
9. **I/O & Disk Type:** Để mặc định (LSI Logic, NVMe/SCSI) $\rightarrow$ **Next**.
10. **Select a Disk:** Chọn **Create a new virtual disk** $\rightarrow$ **Next**.
11. **Disk Capacity:** Điền `30.0 GB` $\rightarrow$ Chọn **Split virtual disk into multiple files** $\rightarrow$ **Next** $\rightarrow$ **Finish**.

---

### 4.3. Khởi tạo VM 3: Wazuh AIO Server (Sử dụng ISO trong thư mục `iso ubuntu 22.04.5`)
> 💡 **Khuyến nghị kiến trúc SIEM:** Wazuh AIO Indexer & Manager chạy tương thích 100% chuẩn nhất trên **Ubuntu Server 22.04.5 LTS**. Dùng chung ISO với VM 2 giúp tiết kiệm thời gian và đồng bộ toàn bộ hạ tầng.

1. Chọn **File** $\rightarrow$ **New Virtual Machine...** $\rightarrow$ Chọn **Custom (advanced)** $\rightarrow$ **Next**.
2. Hardware compatibility: Mặc định $\rightarrow$ **Next**.
3. **Guest OS Installation:** Chọn *Installer disc image file (iso)* $\rightarrow$ Browse vào thư mục **`iso ubuntu 22.04.5`** $\rightarrow$ Chọn file ISO bên trong $\rightarrow$ **Next**.
4. **Guest operating system:** Chọn **Linux**, Version: **Ubuntu 64-bit** $\rightarrow$ **Next**.
5. **Virtual machine name:** Đặt tên `VM3-Wazuh-SIEM` $\rightarrow$ Chọn thư mục lưu trữ máy ảo trên SSD $\rightarrow$ **Next**.
6. **Processor Configuration:** 
   * Number of processors: `2`
   * Number of cores per processor: `2` (**Tổng cộng: 4 Cores** - Bắt buộc cho Wazuh Indexer) $\rightarrow$ **Next**.
7. **Memory for the Virtual Machine:** Điền `8192 MB` (**8 GB RAM** - Bắt buộc để cấp 4GB JVM Heap) $\rightarrow$ **Next**.
8. **Network Connection:** Chọn **Use custom virtual network** $\rightarrow$ Chọn **`VMnet8 (NAT)`** $\rightarrow$ **Next**.
9. **I/O & Disk Type:** Để mặc định $\rightarrow$ **Next**.
10. **Disk Capacity:** Điền **`50.0 GB`** (chứa database chỉ mục OpenSearch và log kiểm toán) $\rightarrow$ Chọn **Split virtual disk into multiple files** $\rightarrow$ **Next** $\rightarrow$ **Finish**.

---

## 🌐 5. BƯỚC 3: CÀI ĐẶT OS & THIẾT LẬP IP TĨNH (STATIC IP)

### 5.1. Lưu ý chung khi cài đặt Ubuntu Server trên VM 2 và VM 3:
* **Ngôn ngữ:** English.
* **Network connections:** Có thể để DHCP tạm thời trong lúc cài (sẽ cấu hình IP tĩnh ở bước sau).
* **Storage configuration:** Chọn mặc định (sử dụng toàn bộ đĩa LVM).
* **Profile setup:**
  * Your name: `Administrator`
  * Your server's name: `vm2-web-target` (trên VM 2) và `vm3-wazuh-server` (trên VM 3).
  * Pick a username: `ubuntu` (hoặc `admin`).
  * Choose a password: Tạo mật khẩu dễ nhớ (ví dụ: `151004`).
* **SSH Setup:** Tích chọn `[X] Install OpenSSH server` (Bắt buộc để remote điều khiển từ xa).
* **Featured Server Snaps:** Bỏ qua không chọn snap nào $\rightarrow$ Nhấn **Done** để bắt đầu cài đặt.

---

### 5.2. Cấu hình IP Tĩnh trên VM 2 (Web Target - `192.168.1.20`)
Đăng nhập vào VM 2 sau khi khởi động lại:
1. Xem tên card mạng thực tế:
   ```bash
   ip -br a
   ```
   *(Thường sẽ là `ens33`, `ens160` hoặc `eth0`).*

2. Mở file cấu hình Netplan:
   ```bash
   sudo nano /etc/netplan/00-installer-config.yaml
   ```

3. Cập nhật nội dung chính xác như sau (thay `ens33` nếu tên card khác):
   ```yaml
   network:
     version: 2
     renderer: networkd
     ethernets:
       ens33:
         dhcp4: no
         addresses:
           - 192.168.1.20/24
         routes:
           - to: default
             via: 192.168.1.2
         nameservers:
           addresses: [8.8.8.8, 1.1.1.1]
   ```

4. Áp dụng cấu hình mạng:
   ```bash
   sudo netplan apply
   ip a show ens33
   ```

---

### 5.3. Cấu hình IP Tĩnh trên VM 3 (Wazuh SIEM - `192.168.1.30`)
Đăng nhập vào VM 3:
1. Mở file Netplan:
   ```bash
   sudo nano /etc/netplan/00-installer-config.yaml
   ```

2. Cập nhật nội dung YAML:
   ```yaml
   network:
     version: 2
     renderer: networkd
     ethernets:
       ens33:
         dhcp4: no
         addresses:
           - 192.168.1.30/24
         routes:
           - to: default
             via: 192.168.1.2
         nameservers:
           addresses: [8.8.8.8, 1.1.1.1]
   ```

3. Áp dụng cấu hình mạng:
   ```bash
   sudo netplan apply
   ip a show ens33
   ```

---

### 5.4. Cấu hình IP Tĩnh trên VM 1 (Kali Linux - `192.168.1.10`)
Đăng nhập vào terminal của Kali Linux:
1. Kiểm tra tên kết nối:
   ```bash
   nmcli connection show
   ```
2. Gán IP tĩnh bằng lệnh `nmcli`:
   ```bash
   sudo nmcli connection modify "Wired connection 1" \
     ipv4.method manual \
     ipv4.addresses 192.168.1.10/24 \
     ipv4.gateway 192.168.1.2 \
     ipv4.dns "8.8.8.8 1.1.1.1"

   # Khởi động lại card mạng
   sudo nmcli connection up "Wired connection 1"
   ip a
   ```

---

## ⏰ 6. BƯỚC 4: ĐỒNG BỘ THỜI GIAN (NTP) & CÀI GÓI NỀN TẢNG

### 6.1. Đồng bộ thời gian hệ thống (Thực hiện trên CẢ 3 VM)
> [!IMPORTANT]
> Nếu thời gian trên VM 2 và VM 3 bị lệch quá 5 phút so với thời gian thực tế:
> 1. Chứng chỉ SSL tự ký của Wazuh sẽ bị lỗi `Certificate has expired or is not yet valid`.
> 2. Wazuh Agent sẽ không thể xác thực vào cổng 1514 của Manager.
> 3. Các sự kiện log trên Dashboard sẽ bị sai lệch mốc thời gian (Time drift).

Chạy các lệnh sau trên cả 3 máy:
```bash
sudo timedatectl set-timezone Asia/Ho_Chi_Minh
sudo timedatectl set-ntp true
sudo timedatectl status
```
*(Đảm bảo dòng `NTP service: active` và `System clock synchronized: yes`)*.

---

### 6.2. Cài đặt Docker Engine & Docker Compose trên VM 2 (Web Target)
Đăng nhập vào VM 2 và chạy script cài đặt Docker chính thức:
```bash
# 1. Cài các công cụ phụ trợ
sudo apt update && sudo apt install -y curl wget git jq htop net-tools ufw

# 2. Cài Docker tự động
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# 3. Phân quyền cho user hiện tại không cần gõ sudo khi chạy docker
sudo usermod -aG docker $USER

# 4. Kiểm tra phiên bản Docker & Compose
newgrp docker
docker --version
docker compose version
```

---

## ✅ 7. BƯỚC 5: NGHIỆM THU MA TRẬN KẾT NỐI (CHECKPOINT 0)

Mở terminal trên từng máy ảo và thực hiện kiểm tra ping chéo:

### 1. Kiểm tra từ VM 1 (Attacker - `192.168.1.10`):
```bash
ping -c 3 192.168.1.20    # Ping sang VM 2 (Kỳ vọng: 0% packet loss)
ping -c 3 192.168.1.30    # Ping sang VM 3 (Kỳ vọng: 0% packet loss)
ping -c 3 8.8.8.8         # Ping Internet (Kỳ vọng: 0% packet loss)
```

### 2. Kiểm tra từ VM 2 (Web Target - `192.168.1.20`):
```bash
ping -c 3 192.168.1.10    # Ping sang VM 1 (Kỳ vọng: 0% packet loss)
ping -c 3 192.168.1.30    # Ping sang VM 3 (Kỳ vọng: 0% packet loss)
curl -I https://google.com # Kiểm tra DNS và HTTP Internet
```

### 3. Kiểm tra từ VM 3 (Wazuh SIEM - `192.168.1.30`):
```bash
ping -c 3 192.168.1.10    # Ping sang VM 1
ping -c 3 192.168.1.20    # Ping sang VM 2
curl -I https://google.com
```

### 4. Kiểm tra SSH từ máy Host (Windows) vào các máy ảo:
Từ Windows Terminal / PowerShell của máy thật:
```powershell
ssh ubuntu@192.168.1.20
ssh ubuntu@192.168.1.30
```

---

## 🎯 KẾT LUẬN GIAI ĐOẠN 0
Khi toàn bộ các tiêu chí trên đạt trạng thái **PASS**, hạ tầng ảo hóa VMware của bạn đã sẵn sàng 100%. Bạn có thể chuyển sang thực hiện **Giai đoạn 1** (Khởi tạo repo và nạp file `.env`) theo hướng dẫn trong [**`docs/deployment-plan.md`**](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/docs/deployment-plan.md).

