#!/bin/bash
# detect_project.sh - Identifies project type from current directory

if [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    echo "spring-boot"
    exit 0
fi

if [ -f "package.json" ]; then
    if grep -q '"expo"' package.json 2>/dev/null; then
        echo "expo"
        exit 0
    fi

    if grep -q '"next"' package.json 2>/dev/null; then
        echo "nextjs"
        exit 0
    fi

    if grep -q '"react"' package.json 2>/dev/null; then
        echo "react"
        exit 0
    fi

    echo "node"
    exit 0
fi

echo "unknown"
exit 1
