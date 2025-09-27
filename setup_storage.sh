#!/bin/bash
# Complete USB Storage Pool Setup with Email & Disconnection Alerts
# by G.T

set -e

echo "=== Complete USB Storage Pool Setup ==="

# 1. Εγκατάσταση βασικών πακέτων
sudo apt update
sudo apt install -y snapraid samba mailutils postfix

# 2. Ρύθμιση Email (Gmail)
echo "=== Ρύθμιση Email Notifications ==="
read -p "Δώσε το Gmail σου (example@gmail.com): " USER_EMAIL
read -p "Δώσε το App Password σου: " APP_PASSWORD

# Ρύθμιση Postfix για Gmail
sudo tee /etc/postfix/sasl_passwd >/dev/null <<EOF
[smtp.gmail.com]:587 $USER_EMAIL:$APP_PASSWORD
EOF

sudo chmod 600 /etc/postfix/sasl_passwd
sudo postmap /etc/postfix/sasl_passwd

sudo tee -a /etc/postfix/main.cf >/dev/null <<EOF
relayhost = [smtp.gmail.com]:587
smtp_use_tls = yes
smtp_sasl_auth_enable = yes
smtp_sasl_security_options =
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
EOF

sudo systemctl restart postfix

# 3. Επιλογή δίσκων
echo
echo "Διαθέσιμοι δίσκοι:"
lsblk -o NAME,SIZE,UUID,MOUNTPOINT,FSTYPE

echo
echo "=== Επιλογή Parity Δίσκου ==="
read -p "Δώσε το UUID του parity δίσκου: " PARITY_UUID

echo
echo "=== Επιλογή Data Δίσκων ==="
echo "Γράψε τα UUID των data δίσκων (ένα-ένα)"
echo "Όταν τελειώσεις, γράψε '0' για να σταματήσεις"
echo ""

DATA_UUIDS=()
i=1
while true; do
    read -p "UUID data δίσκου $i (ή '0' για τέλος): " UUID
        
            if [ "$UUID" = "0" ]; then
                    break
                        fi
                            
                                if [ ! -z "$UUID" ]; then
                                        DATA_UUIDS+=("$UUID")
                                                i=$((i+1))
                                                    fi
                                                    done

                                                    # Convert array to space-separated string for later use
                                                    DATA_UUIDS_STR="${DATA_UUIDS[@]}"

                                                    # 4. Mount points
                                                    sudo mkdir -p /mnt/parity
                                                    sudo mkdir -p /mnt/storage

                                                    # 5. Fstab setup
                                                    echo "=== Ρύθμιση fstab ==="
                                                    sudo cp /etc/fstab /etc/fstab.bak

                                                    # Parity disk
                                                    grep -q "$PARITY_UUID" /etc/fstab || \
                                                    echo "UUID=$PARITY_UUID   /mnt/parity   ext4   defaults,nofail   0   2" | sudo tee -a /etc/fstab

                                                    # Data disks
                                                    for UUID in "${DATA_UUIDS[@]}"; do
                                                        grep -q "$UUID" /etc/fstab || \
                                                            echo "UUID=$UUID   /mnt/storage   ext4   defaults,nofail   0   2" | sudo tee -a /etc/fstab
                                                            done

                                                            sudo mount -a

                                                            # 6. SnapRAID configuration
                                                            echo "=== Δημιουργία snapraid.conf ==="
                                                            sudo tee /etc/snapraid.conf >/dev/null <<EOF
                                                            # SnapRAID Configuration
                                                            parity /mnt/parity/snapraid.parity

                                                            content /var/snapraid/snapraid.content
                                                            content /mnt/parity/snapraid.content
                                                            EOF

                                                            i=1
                                                            for UUID in "${DATA_UUIDS[@]}"; do
                                                                echo "data d$i /mnt/storage" | sudo tee -a /etc/snapraid.conf
                                                                    i=$((i+1))
                                                                    done

                                                                    # 7. Email notification script για sync
                                                                    echo "=== Δημιουργία email notification script ==="
                                                                    sudo tee /usr/local/bin/snapraid-sync-email.sh >/dev/null <<EOF
                                                                    #!/bin/bash
                                                                    LOG_FILE="/tmp/snapraid-sync-\$(date +%Y%m%d-%H%M%S).log"
                                                                    EMAIL="$USER_EMAIL"
                                                                    HOSTNAME=\$(hostname)
                                                                    IP_ADDRESS=\$(hostname -I | awk '{print \$1}')

                                                                    {
                                                                        echo "=== SnapRAID Sync Report ==="
                                                                            echo "Host: \$HOSTNAME"
                                                                                echo "IP: \$IP_ADDRESS"
                                                                                    echo "Date: \$(date)"
                                                                                        echo ""

                                                                                            echo "=== Disk Space Before Sync ==="
                                                                                                df -h /mnt/parity /mnt/storage

                                                                                                    echo ""
                                                                                                        echo "=== Starting SnapRAID Sync ==="
                                                                                                            /usr/bin/snapraid sync

                                                                                                                SYNC_EXIT=\$?

                                                                                                                    echo ""
                                                                                                                        echo "=== Sync Finished ==="
                                                                                                                            echo "Exit Code: \$SYNC_EXIT"
                                                                                                                                echo "Time: \$(date)"

                                                                                                                                    echo ""
                                                                                                                                        echo "=== SnapRAID Status ==="
                                                                                                                                            /usr/bin/snapraid status

                                                                                                                                                echo ""
                                                                                                                                                    echo "=== Disk Space After Sync ==="
                                                                                                                                                        df -h /mnt/parity /mnt/storage

                                                                                                                                                        } | tee "\$LOG_FILE"

                                                                                                                                                        # Send email notification
                                                                                                                                                        if [ \$SYNC_EXIT -eq 0 ]; then
                                                                                                                                                            mail -s "✅ SnapRAID Sync SUCCESS - \$HOSTNAME" "\$EMAIL" < "\$LOG_FILE"
                                                                                                                                                                echo "Sync completed successfully. Email sent."
                                                                                                                                                                else
                                                                                                                                                                    mail -s "❌ SnapRAID Sync FAILED - \$HOSTNAME" "\$EMAIL" < "\$LOG_FILE"
                                                                                                                                                                        echo "Sync failed. Error email sent."
                                                                                                                                                                            exit 1
                                                                                                                                                                            fi
                                                                                                                                                                            EOF

                                                                                                                                                                            sudo chmod +x /usr/local/bin/snapraid-sync-email.sh

                                                                                                                                                                            # 8. USB Disconnection Monitoring Script
                                                                                                                                                                            echo "=== Δημιουργία USB Disconnection Monitor ==="
                                                                                                                                                                            sudo tee /usr/local/bin/usb-disconnect-monitor.sh >/dev/null <<EOF
                                                                                                                                                                            #!/bin/bash
                                                                                                                                                                            EMAIL="$USER_EMAIL"
                                                                                                                                                                            HOSTNAME=\$(hostname)
                                                                                                                                                                            LOG_FILE="/tmp/usb-monitor-\$(date +%Y%m%d-%H%M%S).log"

                                                                                                                                                                            # Expected UUIDs from setup
                                                                                                                                                                            EXPECTED_UUIDS=("$PARITY_UUID" ${DATA_UUIDS[@]})

                                                                                                                                                                            # Get current connected UUIDs
                                                                                                                                                                            CURRENT_UUIDS=\$(lsblk -o UUID -nr 2>/dev/null | grep -v '^$' | sort | uniq)

                                                                                                                                                                            # Check for missing UUIDs
                                                                                                                                                                            MISSING_UUIDS=()
                                                                                                                                                                            for expected_uuid in "\${EXPECTED_UUIDS[@]}"; do
                                                                                                                                                                                if ! echo "\$CURRENT_UUIDS" | grep -q "\$expected_uuid"; then
                                                                                                                                                                                        MISSING_UUIDS+=("\$expected_uuid")
                                                                                                                                                                                            fi
                                                                                                                                                                                            done

                                                                                                                                                                                            # If missing UUIDs found, send alert
                                                                                                                                                                                            if [ \${#MISSING_UUIDS[@]} -gt 0 ]; then
                                                                                                                                                                                                {
                                                                                                                                                                                                        echo "🚨 USB DISCONNECTION ALERT"
                                                                                                                                                                                                                echo "Host: \$HOSTNAME"
                                                                                                                                                                                                                        echo "Time: \$(date)"
                                                                                                                                                                                                                                echo ""
                                                                                                                                                                                                                                        echo "MISSING USB DRIVES:"
                                                                                                                                                                                                                                                for uuid in "\${MISSING_UUIDS[@]}"; do
                                                                                                                                                                                                                                                            echo " - UUID: \$uuid"
                                                                                                                                                                                                                                                                    done
                                                                                                                                                                                                                                                                            echo ""
                                                                                                                                                                                                                                                                                    echo "CURRENTLY CONNECTED DRIVES:"
                                                                                                                                                                                                                                                                                            lsblk -o NAME,SIZE,UUID,MOUNTPOINT,MODEL | grep -v "loop"
                                                                                                                                                                                                                                                                                                    echo ""
                                                                                                                                                                                                                                                                                                            echo "ACTION REQUIRED: Check physical USB connections!"
                                                                                                                                                                                                                                                                                                                } > "\$LOG_FILE"
                                                                                                                                                                                                                                                                                                                    
                                                                                                                                                                                                                                                                                                                        mail -s "🚨 USB DISCONNECTION ALERT - \$HOSTNAME" "\$EMAIL" < "\$LOG_FILE"
                                                                                                                                                                                                                                                                                                                            echo "USB disconnection alert sent."
                                                                                                                                                                                                                                                                                                                            fi
                                                                                                                                                                                                                                                                                                                            EOF

                                                                                                                                                                                                                                                                                                                            sudo chmod +x /usr/local/bin/usb-disconnect-monitor.sh

                                                                                                                                                                                                                                                                                                                            # 9. Systemd services
                                                                                                                                                                                                                                                                                                                            echo "=== Ρύθμιση systemd services ==="

                                                                                                                                                                                                                                                                                                                            # Sync service (with email)
                                                                                                                                                                                                                                                                                                                            sudo tee /etc/systemd/system/snapraid-sync.service >/dev/null <<EOF
                                                                                                                                                                                                                                                                                                                            [Unit]
                                                                                                                                                                                                                                                                                                                            Description=SnapRAID sync with email notifications
                                                                                                                                                                                                                                                                                                                            After=network.target

                                                                                                                                                                                                                                                                                                                            [Service]
                                                                                                                                                                                                                                                                                                                            Type=oneshot
                                                                                                                                                                                                                                                                                                                            ExecStart=/usr/local/bin/snapraid-sync-email.sh
                                                                                                                                                                                                                                                                                                                            User=root
                                                                                                                                                                                                                                                                                                                            EOF

                                                                                                                                                                                                                                                                                                                            # Sync timer (daily at 2:00 AM)
                                                                                                                                                                                                                                                                                                                            sudo tee /etc/systemd/system/snapraid-sync.timer >/dev/null <<EOF
                                                                                                                                                                                                                                                                                                                            [Unit]
                                                                                                                                                                                                                                                                                                                            Description=Run SnapRAID sync daily at 2AM
                                                                                                                                                                                                                                                                                                                            Requires=snapraid-sync.service

                                                                                                                                                                                                                                                                                                                            [Timer]
                                                                                                                                                                                                                                                                                                                            OnCalendar=*-*-* 02:00:00
                                                                                                                                                                                                                                                                                                                            Persistent=true
                                                                                                                                                                                                                                                                                                                            RandomizedDelaySec=1800

                                                                                                                                                                                                                                                                                                                            [Install]
                                                                                                                                                                                                                                                                                                                            WantedBy=timers.target
                                                                                                                                                                                                                                                                                                                            EOF

                                                                                                                                                                                                                                                                                                                            # USB Monitor service
                                                                                                                                                                                                                                                                                                                            sudo tee /etc/systemd/system/usb-monitor.service >/dev/null <<EOF
                                                                                                                                                                                                                                                                                                                            [Unit]
                                                                                                                                                                                                                                                                                                                            Description=USB Disconnection Monitor
                                                                                                                                                                                                                                                                                                                            After=network.target

                                                                                                                                                                                                                                                                                                                            [Service]
                                                                                                                                                                                                                                                                                                                            Type=oneshot
                                                                                                                                                                                                                                                                                                                            ExecStart=/usr/local/bin/usb-disconnect-monitor.sh
                                                                                                                                                                                                                                                                                                                            User=root
                                                                                                                                                                                                                                                                                                                            EOF

                                                                                                                                                                                                                                                                                                                            # USB Monitor timer (every 30 minutes)
                                                                                                                                                                                                                                                                                                                            sudo tee /etc/systemd/system/usb-monitor.timer >/dev/null <<EOF
                                                                                                                                                                                                                                                                                                                            [Unit]
                                                                                                                                                                                                                                                                                                                            Description=Check for USB disconnections every 30 minutes
                                                                                                                                                                                                                                                                                                                            Requires=usb-monitor.service

                                                                                                                                                                                                                                                                                                                            [Timer]
                                                                                                                                                                                                                                                                                                                            OnCalendar=*-*-* *:0/30:00
                                                                                                                                                                                                                                                                                                                            Persistent=true

                                                                                                                                                                                                                                                                                                                            [Install]
                                                                                                                                                                                                                                                                                                                            WantedBy=timers.target
                                                                                                                                                                                                                                                                                                                            EOF

                                                                                                                                                                                                                                                                                                                            # Scrub service (weekly)
                                                                                                                                                                                                                                                                                                                            sudo tee /etc/systemd/system/snapraid-scrub.service >/dev/null <<'EOF'
                                                                                                                                                                                                                                                                                                                            [Unit]
                                                                                                                                                                                                                                                                                                                            Description=SnapRAID scrub
                                                                                                                                                                                                                                                                                                                            After=network.target

                                                                                                                                                                                                                                                                                                                            [Service]
                                                                                                                                                                                                                                                                                                                            Type=oneshot
                                                                                                                                                                                                                                                                                                                            ExecStart=/bin/bash -c '/usr/bin/snapraid scrub 2>&1 | tee /tmp/snapraid-scrub.log; exit 0'
                                                                                                                                                                                                                                                                                                                            User=root
                                                                                                                                                                                                                                                                                                                            EOF

                                                                                                                                                                                                                                                                                                                            # Scrub timer (weekly on Sunday at 3:00 AM)
                                                                                                                                                                                                                                                                                                                            sudo tee /etc/systemd/system/snapraid-scrub.timer >/dev/null <<EOF
                                                                                                                                                                                                                                                                                                                            [Unit]
                                                                                                                                                                                                                                                                                                                            Description=Run SnapRAID scrub weekly
                                                                                                                                                                                                                                                                                                                            Requires=snapraid-scrub.service

                                                                                                                                                                                                                                                                                                                            [Timer]
                                                                                                                                                                                                                                                                                                                            OnCalendar=Sun *-*-* 03:00:00
                                                                                                                                                                                                                                                                                                                            Persistent=true

                                                                                                                                                                                                                                                                                                                            [Install]
                                                                                                                                                                                                                                                                                                                            WantedBy=timers.target
                                                                                                                                                                                                                                                                                                                            EOF

                                                                                                                                                                                                                                                                                                                            sudo systemctl daemon-reload
                                                                                                                                                                                                                                                                                                                            sudo systemctl enable --now snapraid-sync.timer
                                                                                                                                                                                                                                                                                                                            sudo systemctl enable --now usb-monitor.timer
                                                                                                                                                                                                                                                                                                                            sudo systemctl enable --now snapraid-scrub.timer

                                                                                                                                                                                                                                                                                                                            # 10. Samba share configuration
                                                                                                                                                                                                                                                                                                                            echo "=== Ρύθμιση Samba Share ==="
                                                                                                                                                                                                                                                                                                                            sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

                                                                                                                                                                                                                                                                                                                            sudo tee -a /etc/samba/smb.conf >/dev/null <<EOF

                                                                                                                                                                                                                                                                                                                            [Storage]
                                                                                                                                                                                                                                                                                                                               path = /mnt/storage
                                                                                                                                                                                                                                                                                                                                  browseable = yes
                                                                                                                                                                                                                                                                                                                                     read only = no
                                                                                                                                                                                                                                                                                                                                        guest ok = yes
                                                                                                                                                                                                                                                                                                                                           create mask = 0664
                                                                                                                                                                                                                                                                                                                                              directory mask = 0775
                                                                                                                                                                                                                                                                                                                                                 force user = root
                                                                                                                                                                                                                                                                                                                                                 EOF

                                                                                                                                                                                                                                                                                                                                                 sudo systemctl restart smbd
                                                                                                                                                                                                                                                                                                                                                 sudo systemctl enable smbd

                                                                                                                                                                                                                                                                                                                                                 # 11. Permissions and final setup
                                                                                                                                                                                                                                                                                                                                                 echo "=== Τελική ρύθμιση δικαιωμάτων ==="
                                                                                                                                                                                                                                                                                                                                                 sudo chmod 755 /mnt/storage
                                                                                                                                                                                                                                                                                                                                                 sudo chown root:root /mnt/storage

                                                                                                                                                                                                                                                                                                                                                 # 12. Test email
                                                                                                                                                                                                                                                                                                                                                 echo "=== Δοκιμή email system ==="
                                                                                                                                                                                                                                                                                                                                                 echo "Test email from SnapRAID setup" | mail -s "✅ SnapRAID Setup Complete - $(hostname)" "$USER_EMAIL"

                                                                                                                                                                                                                                                                                                                                                 # 13. Final info
                                                                                                                                                                                                                                                                                                                                                 echo
                                                                                                                                                                                                                                                                                                                                                 echo "=== Ολοκληρώθηκε! ==="
                                                                                                                                                                                                                                                                                                                                                 echo "📧 Email notifications: $USER_EMAIL"
                                                                                                                                                                                                                                                                                                                                                 echo "💾 Samba share: \\\\$(hostname -I | awk '{print $1}')\\Storage"
                                                                                                                                                                                                                                                                                                                                                 echo "🕒 Auto-sync: Daily at 2:00 AM"
                                                                                                                                                                                                                                                                                                                                                 echo "🔍 USB Monitor: Every 30 minutes"
                                                                                                                                                                                                                                                                                                                                                 echo "🧹 Auto-scrub: Weekly on Sunday at 3:00 AM"
                                                                                                                                                                                                                                                                                                                                                 echo ""
                                                                                                                                                                                                                                                                                                                                                 echo "=== Σύνοψη Ρύθμισης ==="
                                                                                                                                                                                                                                                                                                                                                 echo "Parity disk UUID: $PARITY_UUID"
                                                                                                                                                                                                                                                                                                                                                 echo "Data disks UUIDs: ${DATA_UUIDS[@]}"
                                                                                                                                                                                                                                                                                                                                                 echo "Total data disks: ${#DATA_UUIDS[@]}"
                                                                                                                                                                                                                                                                                                                                                 echo ""
                                                                                                                                                                                                                                                                                                                                                 echo "=== Useful Commands ==="
                                                                                                                                                                                                                                                                                                                                                 echo "Check sync status: sudo systemctl status snapraid-sync.timer"
                                                                                                                                                                                                                                                                                                                                                 echo "Manual sync: sudo /usr/local/bin/snapraid-sync-email.sh"
                                                                                                                                                                                                                                                                                                                                                 echo "Check USB status: sudo /usr/local/bin/usb-disconnect-monitor.sh"
                                                                                                                                                                                                                                                                                                                                                 echo "Check disks: snapraid status"
                                                                                                                                                                                                                                                                                                                                                 echo "Samba status: sudo systemctl status smbd"
                                                                                                                                                                                                                                                                                                                                                 echo ""
                                                                                                                                                                                                                                                                                                                                                 echo "=== Recovery Info ==="
                                                                                                                                                                                                                                                                                                                                                 echo "Αν χαλάσει USB: Αντικατάσταση + snapraid fix"
                                                                                                                                                                                                                                                                                                                                                 echo "Προστατεύονται μέχρι ${#DATA_UUIDS[@]} data disk failures"
                                                                                                                                                                                                                                                                                                                                                 echo ""
                                                                                                                                                                                                                                                                                                                                                 echo "=== Next Steps ==="
                                                                                                                                                                                                                                                                                                                                                 echo "1. Check your email for the test message"
                                                                                                                                                                                                                                                                                                                                                 echo "2. Access the share from your network"
                                                                                                                                                                                                                                                                                                                                                 echo "3. Monitor the first automatic sync tomorrow at 2:00 AM"
