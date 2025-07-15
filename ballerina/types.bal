// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.org).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

# Message type represents a message with content, error information, metadata, and properties.
public type Message record {|
    # Unique identifier for the message
    readonly string id;
    # The name of the handler chain that processed this message
    readonly string handlerChainName;
    # The actual content of the message, which can be of anydata type
    anydata content;
    # Optional error message if an error occurred during processing
    string errorMsg?;
    # Optional stack trace of the error if available
    string[] errorStackTrace?;
    # Additional error details, which can include anydata type
    map<anydata> errorDetails?;
    # A map of errors associated with specific destinations, where the key is the destination name and the value is an `ErrorInfo` record
    map<ErrorInfo> destinationErrors?;
    # Metadata associated with the message, such as desctinations to skip
    MessageMetadata metadata = {};
    # A map of additional properties associated with the message
    map<anydata> properties = {};
    # A map of successful destination results
    map<anydata> destinationResults?;
|};

# Error information type.
public type ErrorInfo record {|
    # A descriptive error message
    string message;
    # An array of strings representing the stack trace of the error
    string[] stackTrace;
    # A map containing additional details about the error, which can include any data type
    map<anydata> detail;
    # An optional cause of the error, which can be another error or an error info
    ErrorInfo cause?;
|};

# Message metadata.
public type MessageMetadata record {|
    # An array of destination names that should be skipped when processing the message
    string[] destinationsToSkip = [];
|};

# Source execution result.
type SourceExecutionResult record {|
    # The message that was processed
    Message message;
|};

# Channel execution success result.
public type ExecutionSuccess record {|
    # The message that was processed
    Message message;
    # A map of destination names to their respective results
    map<anydata> destinationResults = {};
|};
