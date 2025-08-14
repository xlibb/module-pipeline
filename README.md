# Ballerina Pipeline Module

[![Build](https://github.com/xlibb/module-pipeline/actions/workflows/build-timestamped-master.yml/badge.svg)](https://github.com/xlibb/module-pipeline/actions/workflows/build-timestamped-master.yml)
[![codecov](https://codecov.io/gh/xlibb/module-pipeline/branch/main/graph/badge.svg)](https://codecov.io/gh/xlibb/module-pipeline)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/xlibb/module-pipeline.svg)](https://github.com/xlibb/module-pipeline/commits/main)
[![Github issues](https://img.shields.io/github/issues/xlibb/module-pipeline/module/pipe.svg?label=Open%20Issues)](https://github.com/xlibb/module-pipeline/labels/module%2Fpipe)
[![GraalVM Check](https://github.com/xlibb/module-pipeline/actions/workflows/build-with-bal-test-graalvm.yml/badge.svg)](https://github.com/xlibb/module-pipeline/actions/workflows/build-with-bal-test-graalvm.yml)

Building message-driven applications often involves complex tasks such as data transformation, message filtering, and reliable delivery to multiple systems. Developers frequently find themselves writing repetitive code for common patterns like retries, error handling, and parallel delivery. This leads to increased development time, inconsistent implementations, and systems that are harder to maintain and evolve.

This package simplifies these challenges by offering a standardized, declarative way to define message pipelines. It centralizes message flow management, reduces boilerplate code, and makes it easier to build resilient, fault-tolerant applications, thereby improving developer experience and promoting consistent, reliable integration patterns across Ballerina projects.

### Core components

The package provides a set of core components that facilitate message-driven application development.

#### Handler

The `Handler` is the fundamental building block of the handler chain. It represents a processing unit that can either process messages or serve as a destination for them. Handlers can be configured with various properties, such as retry policies and error handling strategies.

##### Processor

The message processors are just Ballerina functions that are annotated to indicate their type and purpose. All processors are assumed to be *idempotent*, meaning that running them multiple times with the same input will always produce the same result. This is crucial for safe message replay. It is developer's responsibility to ensure that the logic within these processors adheres to this principle.

The package provides three types of processors:

- **Filter**: A processor that can drop messages based on a condition. This accepts the *Context* and returns a boolean indicating whether the message should continue processing.
  ```ballerina
  @pipeline:Filter {id: "filter"}
  isolated function filter(pipeline:MessageContext context) returns boolean|error {
      // Check some condition on the message
  }
  ```
- **Transformer**: A processor that modifies the message content or metadata. It accepts the *Context* and returns a modified message content.
  ```ballerina
  @pipeline:Transformer {id: "transformer"}
  isolated function transformer(pipeline:MessageContext context) returns anydata|error {
      // Modify the message content or metadata
      // Return the modified message content
  }
  ```
- Generic Processor: A processor that can perform any action on the *Context*. It accepts the *Context* and returns nothing.
  ```ballerina
  @pipeline:Processor {id: "generic"}
  isolated function generic(pipeline:MessageContext context) returns error? {
      // Perform any action on the context
  }
  ```

#### Destination

A destination is similar to a generic processor but is used to deliver the message to an external system or endpoint. It accepts a copy of the *Context* and returns an error if the delivery fails. Additionally, it can return any result that is relevant to the delivery operation, such as a confirmation or status.

A destination can be configured with retry policies to ensure reliable delivery.

```ballerina
@pipeline:Destination {
    id: "destination"
    retryConfig: {
        maxRetries: 3,
        retryInterval: 2
    }
}
isolated function destination(pipeline:MessageContext context) returns anydata|error {
    // Deliver the message to an external system or endpoint
}
```

#### Message

The `Message` is the core data structure that represents the message being processed. It contains the actual payload and any metadata required for processing. The `Message` is passed through the handler chain, allowing each processor to access and modify it as needed.

#### Message context

The `MessageContext` is a mutable container that holds the current state of the message being processed. It encapsulates the `Message` itself, along with any additional properties or metadata that processors and destinations need to share or update during the message's journey through the handler chain. This allows for a flexible and dynamic processing flow, where each component can access and modify the context as needed.

The following methods are available on the `pipeline:MessageContext`:

| Method                                   | Description                                                                |
|------------------------------------------|----------------------------------------------------------------------------|
| `getContent()`                           | Returns the message content as `anydata`.                                  |
| `getContentWithType()`                   | Returns the message content as a specific type.                            |
| `getId()`                                | Returns the unique identifier of the message.                              |
| `setProperty(string key, anydata value)` | Sets a property in the context.                                            |
| `getProperty(string key)`                | Gets a property from the context.                                          |
| `getPropertyWithType(string key)`        | Gets a property from the context with a specific type.                     |
| `hasProperty(string key)`                | Checks if a property exists in the context.                                |
| `removeProperty(string key)`             | Removes a property from the context.                                       |
| `toRecord()`                             | Converts the context to a record type for easier inspection and debugging. |

#### Failure store

The `FailureStore` is a crucial component that captures messages that fail during processing or delivery. It stores the original message content along with a snapshot of the `MessageContext` at the time of failure. This allows for later inspection, debugging, and potential replay of failed messages.

#### Replay listener

The `ReplayListener` is an optional component that listens for failed messages stored in the `FailureStore` or a dedicated `ReplayStore`. It attempts to re-process these messages through the handler chain's defined pipeline, including retry policies. If a message consistently fails replay attempts, it can be routed to a Dead Letter Store for manual intervention.

#### Handler chain

The `HandlerChain` is the central component that orchestrates the entire message processing flow. It manages the sequence of handlers, the `MessageContext`, and the interaction with the `FailureStore` and `ReplayListener`. The `HandlerChain` is responsible for executing the defined processing logic, handling failures, and ensuring messages are processed in a consistent manner.

```ballerina
pipeline:HandlerChain handlerChain = check new(
    name = "exampleHandlerChain", // Name of the handler chain
    processors = [
        filter, // a Filter processor
        transformer, // a Transformer processor
        generic // a generic Processor
    ],
    destinations = [
        destination // a Destination handler
    ],
    failureStore = failureStore, // an instance of FailureStore
    replayListenerConfig = {
        pollingInterval: 5, // Polling interval for the replay listener
        maxRetries: 3, // Maximum retries for replaying messages
        retryInterval: 2 // Interval between retries
        deadLetterStore: deadLetterStore // Dead Letter Store
        replayStore: replayStore // Optional Replay Store
    }
);
```

### Component interaction

The flow of a message through a `pipeline:HandlerChain` is meticulously orchestrated to ensure reliability and flexible processing:

1. **Message Ingress:** A raw message content (e.g., a string, json, byte[], or anydata) enters the Handler Chain through its `execute` method. This content typically originates from an external source (e.g., an HTTP request, a message queue subscription, a file read, or a direct function call).

2. **Context Creation:** The Handler Chain immediately wraps this incoming raw content into a Message record. This Message is then encapsulated within a new Message Context instance. This Message Context becomes the central, dynamic container for all subsequent operations, allowing processors and destinations to share and update state throughout the message's journey. A unique identifier is assigned to the Message and stored within the Context.

3. **Sequential Processing (Processors):**

    - The Handler Chain iteratively processes the Message Context through its configured Processors in the defined order.
    - Each Processor receives the Message Context as input. It can access and modify the message's content, update its internal metadata, or add new properties to the Message Context itself.

    - **Filtering:** If a Filter processor returns false (indicating the message should be dropped) or an error, the Handler Chain immediately stops further processing for that message within the current handler chain. The message is considered successfully handled (dropped) and is not passed to subsequent processors or destinations.

    - **Error Handling (Processors):** If any Processor encounters an error and returns an error type, the Handler Chain catches this exception. It then persists the original Message and the initial Message Context into the configured Failure Store. This ensures that the state leading to the failure is preserved for later inspection and potential replay.

4. **Parallel Delivery (Destinations):**

    - If the message successfully traverses all Processors (i.e., it wasn't dropped and no processor returned an unhandled error), the Handler Chain proceeds to its Destinations flow.

    - The Destinations configured in the Handler Chain are executed in parallel.

    - Crucially, each Destination receives a copy of the Message Context (which includes the fully processed Message). This ensures isolation; actions performed by one destination (e.g., external API calls, logging specific to that destination) do not unintentionally interfere with the Message Context being used by other concurrently executing destinations.

    - **Error Handling (Destinations):** If any Destination fails to deliver the message (returns an error), the Handler Chain intercepts this. Similar to processor failures, the original Message and the initial Message Context are sent to the Failure Store.

    - **Execution Result:** If all Destinations succeed, the execute method returns a `pipeline:ExecutionSuccess` containing a map of results from each destination, keyed by the destination's name.

5. **Failure Store Interaction:**

    - The Failure Store is a required configuration for the Handler Chain.

    - When enabled, it acts as the central repository for messages that encounter an error during either the Processor phase or the Destination phase.

    - The Handler Chain serializes and persists the Message and the state of its Message Context into the Failure Store. This comprehensive capture is vital for debugging, re-analyzing failure causes, and enabling the replay mechanism.

6. **Replay Mechanism:**

    - The Handler Chain can be configured with an optional Replay Listener (leveraging `ballerina/messaging:StoreListener`) that automatically monitors the Failure Store/Replay Store to reply failed messages.

    - The replayListener will poll the Failure Store/Replay Store at a configured `pollingInterval` for new failed messages.

    - When a failed message is retrieved by the replayListener, it triggers a re-processing attempt through the original Handler Chain's execute method, but with an intelligent context.

    - **Intelligent Replay:** During replay, the Handler Chain inspects the Message Context snapshot. If the Message Context contains information about destinations that already successfully processed the message in previous attempts, the Handler Chain will intelligently skip those already successful Destinations. This prevents redundant deliveries to systems that have already received the message, ensuring idempotency at the destination level where possible and preventing unintended side effects.

    - If a replayed message consistently fails even after the configured number of maxRetries, it can be sent to a Dead Letter Store (another `messaging:Store` instance) for manual inspection or further automated handling outside the main handler chain flow.

![Handler Chain Interaction](https://raw.githubusercontent.com/xlibb/module-pipeline/main/docs/resources/handler-chain-interaction.png)


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
