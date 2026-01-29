#!/bin/bash
# detect_server.sh - Finds running dev server on common ports

PORTS=(3000 8080 8081)

for port in "${PORTS[@]}"; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" 2>/dev/null | grep -qE "200|302|304|401|403"; then
        echo "$port"
        exit 0
    fi
done

echo "none"
exit 1
