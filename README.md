# Ballerina Pipeline Module

[![Build](https://github.com/xlibb/module-pipeline/actions/workflows/build-timestamped-master.yml/badge.svg)](https://github.com/xlibb/module-pipeline/actions/workflows/build-timestamped-master.yml)
[![codecov](https://codecov.io/gh/xlibb/module-pipeline/branch/main/graph/badge.svg)](https://codecov.io/gh/xlibb/module-pipeline)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/xlibb/module-pipeline.svg)](https://github.com/xlibb/module-pipeline/commits/main)
[![Github issues](https://img.shields.io/github/issues/xlibb/module-pipeline/module/pipe.svg?label=Open%20Issues)](https://github.com/xlibb/module-pipeline/labels/module%2Fpipe)
[![GraalVM Check](https://github.com/xlibb/module-pipeline/actions/workflows/build-with-bal-test-graalvm.yml/badge.svg)](https://github.com/xlibb/module-pipeline/actions/workflows/build-with-bal-test-graalvm.yml)

This library provides a way to create a chain of handlers that can process data and send it to multiple destinations.

## Build from the source

### Set up the prerequisites

1.  Download and install Java SE Development Kit (JDK) version 21 (from one of the following locations).

    - [Oracle](https://www.oracle.com/java/technologies/javase-jdk21-downloads.html)

    - [OpenJDK](https://adoptopenjdk.net/)

      > **Note:** Set the `JAVA_HOME` environment variable to the path name of the directory into which you installed JDK.

2.  Export your GitHub Personal access token with the read package permissions as follows.

    ```
    export packageUser=<Username>
    export packagePAT=<Personal access token>
    ```

### Build the source

Execute the commands below to build from the source.

1. To build the library:

   ```
   ./gradlew clean build
   ```

2. To run the integration tests:
   ```
   ./gradlew clean test
   ```
3. To build the module without the tests:
   ```
   ./gradlew clean build -x test
   ```
4. To debug module implementation:
   ```
   ./gradlew clean build -Pdebug=<port>
   ./gradlew clean test -Pdebug=<port>
   ```
5. To debug the module with Ballerina language:
   ```
   ./gradlew clean build -PbalJavaDebug=<port>
   ./gradlew clean test -PbalJavaDebug=<port>
   ```
6. Publish ZIP artifact to the local `.m2` repository:
   ```
   ./gradlew clean build publishToMavenLocal
   ```
7. Publish the generated artifacts to the local Ballerina central repository:
   ```
   ./gradlew clean build -PpublishToLocalCentral=true
   ```
8. Publish the generated artifacts to the Ballerina central repository:
   ```
   ./gradlew clean build -PpublishToCentral=true
   ```

## Code of conduct

All the contributors are encouraged to read the [Ballerina Code of Conduct](https://ballerina.io/code-of-conduct).
