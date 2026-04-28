#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Locate Java 17+ — check JAVA_HOME, common OL8/OL9 paths, then PATH
JAVA_BIN=""
for candidate in \
    "${JAVA_HOME:+$JAVA_HOME/bin/java}" \
    /usr/lib/jvm/java-17-openjdk/bin/java \
    /usr/lib/jvm/java-17/bin/java \
    /usr/lib/jvm/java-17-openjdk-amd64/bin/java \
    "$(command -v java 2>/dev/null)"; do
    [ -x "$candidate" ] || continue
    ver=$("$candidate" -version 2>&1 | awk -F '"' '/version/{print $2}' | cut -d. -f1)
    [ "${ver:-0}" -ge 17 ] 2>/dev/null && JAVA_BIN="$candidate" && break
done

if [ -z "$JAVA_BIN" ]; then
    echo "ERROR: Java 17 or later is required but was not found."
    echo "       Install it with: sudo dnf install java-17-openjdk"
    exit 1
fi

JAR="$SCRIPT_DIR/target/sample-app-springboot-0.0.1-SNAPSHOT.jar"
if [ ! -f "$JAR" ]; then
    echo "Building (target jar missing; needs internet for Maven Central)..."
    "$SCRIPT_DIR/mvnw" -f "$SCRIPT_DIR/pom.xml" package -DskipTests -q
fi

echo "Starting sample-app-springboot on port 8090 (using $JAVA_BIN)..."
"$JAVA_BIN" -jar "$JAR" &
echo $! > "$SCRIPT_DIR/app.pid"
echo "PID: $(cat "$SCRIPT_DIR/app.pid")"
