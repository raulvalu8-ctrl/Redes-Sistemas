#!/bin/bash

echo ""
echo "-------------------------------"
echo "Reporte del servidor"
echo "-------------------------------"

echo "Hostname:"
hostname
echo ""

echo "Direccion IP:"
ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1
echo ""

echo "Uso de disco:"
df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs
echo ""

echo "-------------------------------"