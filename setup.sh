#! /bin/bash
# Скрипт установки скрипта который устанав
echo "Скрипт установки скрипта который устанав v.1.0"

cat > /opt/script.sh << 'EOF'
#! /bin/bash
while true; do
  date >> /opt/my.log
  sleep 1
done
EOF

echo "Запущен скрипт: /opt/script.sh"