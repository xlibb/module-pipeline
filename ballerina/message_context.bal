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
import ballerina/jballerina.java;

# MessageContext encapsulates the message and the relevant properties. Additionally,
# it provides methods to manipulate the message properties and metadata.
public isolated class MessageContext {
    private Message message;

    # Initializes a new instance of MessageContext with the provided message.
    #
    # + message - The message to initialize the context with
    # + return - A new instance of MessageContext
    isolated function init(*Message message) {
        self.message = {...message.clone()};
    }

    # Get the unique identifier of the message.
    #
    # + return - The unique identifier of the message
    public isolated function getId() returns string {
        lock {
            return self.message.id.clone();
        }
    }

    # Get the message as a record.
    #
    # + return - A record version of the message
    public isolated function toRecord() returns Message {
        lock {
            return self.message.clone();
        }
    }

    # Get the content of the message.
    #
    # + return - The content of the message, which can be of anydata type
    public isolated function getContent() returns anydata {
        lock {
            return self.message.content.clone();
        }
    }

    # Get the name of the handler chain that processed this message.
    #
    # + return - The name of the handler chain
    public isolated function getHandlerChainName() returns string {
        lock {
            return self.message.handlerChainName.clone();
        }
    }

    # Get the content of the message with a specific type.
    #
    # + targetType - The type to which the content should be converted, defaults to anydata
    # + return - The content of the message converted to the specified type, or an error
    # if the conversion fails
    public isolated function getContentWithType(typedesc<anydata> targetType = <>) returns targetType|Error = @java:Method {
        'class: "io.xlibb.pipeline.MessageContextUtils"
    } external;

    # Set the content of the message.
    #
    # + content - The new content to set for the message
    isolated function setContent(anydata content) {
        lock {
            self.message.content = content.clone();
        }
    }

    # Get message property by key.
    #
    # + key - The key of the property to retrieve
    # + return - The value of the property if it exists, otherwise panics
    public isolated function getProperty(string key) returns anydata {
        lock {
            if self.message.properties.hasKey(key) {
                return self.message.properties[key].clone();
            } else {
                panic error Error("Property with key '" + key + "' not found");
            }
        }
    }

    # Get message property by key with a specific type.
    #
    # + key - The key of the property to retrieve
    # + targetType - The type to which the property value should be converted, defaults to anydata
    # + return - The value of the property converted to the specified type, or an error
    # if the conversion fails. The function will panic if the property does not exist
    public isolated function getPropertyWithType(string key, typedesc<anydata> targetType = <>) returns targetType|Error = @java:Method {
        'class: "io.xlibb.pipeline.MessageContextUtils"
    } external;

    # Set a property in the message.
    #
    # + key - The key of the property to set
    # + value - The value to set for the property
    public isolated function setProperty(string key, anydata value) {
        lock {
            self.message.properties[key] = value.clone();
        }
    }

    # Remove a property from the message.
    #
    # + key - The key of the property to remove
    # + return - If the property exists, it is removed; otherwise, it panics
    public isolated function removeProperty(string key) returns anydata {
        lock {
            if self.message.properties.hasKey(key) {
                return self.message.properties.remove(key).clone();
            } else {
                panic error Error("Property with key '" + key + "' not found");
            }
        }
    }

    # Check if a property exists in the message.
    #
    # + key - The key of the property to check
    # + return - Returns true if the property exists, otherwise false
    public isolated function hasProperty(string key) returns boolean {
        lock {
            return self.message.properties.hasKey(key);
        }
    }

    # Returns whether the destination needs to be skipped or not.
    #
    # + destination - The name of the destination to check
    # + return - Returns true if the destination is skipped, otherwise false
    isolated function isDestinationSkipped(string destination) returns boolean {
        lock {
            return self.message.metadata.destinationsToSkip.indexOf(destination) !is ();
        }
    }

    # Mark a destination to be skipped.
    #
    # + destination - The name of the destination to skip
    isolated function skipDestination(string destination) {
        lock {
            if !self.isDestinationSkipped(destination) {
                self.message.metadata.destinationsToSkip.push(destination);
            }
        }
    }

    # Set the destination results on the message context.
    #
    # + results - A map of destination names with their respective results
    isolated function setDestinationResults(map<anydata> results) {
        lock {
            self.message.destinationResults = results.clone();
        }
    }

    # Add a destination error to the message context.
    #
    # + destinationName - The name of the destination where the error occurred
    # + err - The error to set on the message context
    isolated function addDestinationError(string destinationName, error err) {
        lock {
            ErrorInfo errorInfo = createErrorInfo(err);
            if self.message.destinationErrors is map<ErrorInfo> {
                self.message.destinationErrors[destinationName] = errorInfo;
            } else {
                self.message.destinationErrors = {[destinationName]: errorInfo};
            }
        }
    }

    # Set an error message on the message context.
    #
    # + msg - The error message to set on the message context
    isolated function setErrorMessage(string msg) {
        lock {
            self.message.errorMsg = msg;
        }
    }

    # Set an error to the message context.
    #
    # + msg - The error message to set on the message context
    # + err - The error to set on the message context
    isolated function setError(error err, string? msg = ()) {
        lock {
            string errorMsg = msg is string ? msg : err.message();
            self.message.errorMsg = errorMsg;
            self.message.errorStackTrace = createStackTrace(err);
            self.message.errorDetails = createErrorDetailMap(err);
        }
    }

    # Clone the message context.
    #
    # + return - A new instance of MessageContext with the same message
    isolated function clone() returns MessageContext {
        lock {
            return new (self.message.clone());
        }
    }

    # Clean the message for replay. This removes any metadata related to previous executions
    isolated function cleanMessageForReplay() {
        lock {
            self.message.errorMsg = ();
            self.message.errorStackTrace = ();
            self.message.errorDetails = ();
            self.message.destinationErrors = ();
            self.message.destinationResults = {};
        }
    }
}

isolated function createErrorInfo(error err) returns ErrorInfo => {
    message: err.message(),
    stackTrace: createStackTrace(err),
    detail: createErrorDetailMap(err),
    cause: createCauseErrorInfo(err)
};

isolated function createStackTrace(error err) returns string[] {
    error:StackFrame[] stackTrace = err.stackTrace();
    string[] stackTraceStrings = [];
    foreach error:StackFrame frame in stackTrace {
        stackTraceStrings.push(frame.toString());
    }
    return stackTraceStrings;
}

isolated function createErrorDetailMap(error err) returns map<anydata> => err.detail() is map<anydata> ? <map<anydata>>err.detail() : {};

isolated function createCauseErrorInfo(error err) returns ErrorInfo? {
    error? cause = err.cause();
    return cause is error ? createErrorInfo(cause) : ();
}
