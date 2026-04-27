#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export JAVA_HOME=/usr/lib/jvm/java-17

JAR="$SCRIPT_DIR/target/sample-app-springboot-0.0.1-SNAPSHOT.jar"
if [ ! -f "$JAR" ]; then
    echo "Building (target jar missing; needs internet for Maven Central)..."
    "$SCRIPT_DIR/mvnw" -f "$SCRIPT_DIR/pom.xml" package -DskipTests -q
fi

echo "Starting sample-app-springboot on port 8090..."
$JAVA_HOME/bin/java -jar "$JAR" &
echo $! > "$SCRIPT_DIR/app.pid"
echo "PID: $(cat "$SCRIPT_DIR/app.pid")"
