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

import ballerina/test;

@test:Config {
    groups: ["message_ctx_tests"]
}
function testMessageContextGeneralUtils() {
    MessageContext msgCtx = new (id = "12345", content = "Test message", handlerChainName = "testChain");
    MessageContext clonedMsgCtx = msgCtx.clone();
    test:assertEquals(msgCtx.getId(), "12345");
    test:assertEquals(msgCtx.getContent(), "Test message");
    test:assertEquals(msgCtx.getHandlerChainName(), "testChain");

    msgCtx.setContent("Updated message");
    test:assertEquals(msgCtx.getContent(), "Updated message");

    Message recordMsg = msgCtx.toRecord();
    test:assertEquals(recordMsg.id, "12345");
    test:assertEquals(recordMsg.content, "Updated message");

    test:assertEquals(clonedMsgCtx.getId(), "12345");
    test:assertEquals(clonedMsgCtx.getContent(), "Test message");
}

@test:Config {
    groups: ["message_ctx_tests"]
}
function testMessageContextContentWithTypeSuccess() returns error? {
    MessageContext msgCtx = new (id = "12345", content = "Test message", handlerChainName = "testChain");
    test:assertEquals(msgCtx.getId(), "12345");

    string contentWithType = check msgCtx.getContentWithType();
    test:assertEquals(contentWithType, "Test message");

    msgCtx.setContent(42);
    int contentWithTypeInt = check msgCtx.getContentWithType(int);
    test:assertEquals(contentWithTypeInt, 42);

    msgCtx.setContent({"name": "Ballerina", "version": "1.0"});
    map<string> contentWithTypeMap = check msgCtx.getContentWithType();
    test:assertEquals(contentWithTypeMap["name"], "Ballerina");
    test:assertEquals(contentWithTypeMap["version"], "1.0");

    record {|string name; string version;|} contentWithTypeRecord = check msgCtx.getContentWithType();
    test:assertEquals(contentWithTypeRecord.name, "Ballerina");
    test:assertEquals(contentWithTypeRecord.version, "1.0");

    msgCtx.setContent(xml `<message><text>Hello, Ballerina!</text></message>`);
    xml contentWithTypeXml = check msgCtx.getContentWithType();
    test:assertEquals(contentWithTypeXml, xml `<message><text>Hello, Ballerina!</text></message>`);
}

@test:Config {
    groups: ["message_ctx_tests"]
}
function testMessageContextContentWithTypeError() returns error? {
    MessageContext msgCtx = new (id = "12345", content = "1234", handlerChainName = "testChain");
    test:assertEquals(msgCtx.getId(), "12345");

    int|error contentWithTypeInt = msgCtx.getContentWithType(int);
    if contentWithTypeInt is int {
        test:assertFail("Expected error when converting string to int");
    }
    test:assertEquals(contentWithTypeInt.message(), "Failed to convert value to the specified type");

    msgCtx.setContent({"name": "Ballerina", "version": "1.0"});
    map<int>|error contentWithTypeMap = msgCtx.getContentWithType();
    if contentWithTypeMap is map<int> {
        test:assertFail("Expected error when converting map<string> to map<int>");
    }
    test:assertEquals(contentWithTypeMap.message(), "Failed to convert value to the specified type");

    record {|string name; string version; string id;|}|error contentWithTypeRecord = msgCtx.getContentWithType();
    if contentWithTypeRecord is record {} {
        test:assertFail("Expected error when converting to a record with an extra field");
    }
    test:assertEquals(contentWithTypeRecord.message(), "Failed to convert value to the specified type");
}

@test:Config {
    groups: ["message_ctx_tests"]
}
function testMessageContextPropertyMap() {
    MessageContext msgCtx = new (id = "12345", content = "Test message", handlerChainName = "testChain");
    msgCtx.setProperty("key1", "value1");
    msgCtx.setProperty("key2", "value2");

    anydata key1Value = msgCtx.getProperty("key1");
    test:assertEquals(key1Value, "value1");

    anydata key2Value = msgCtx.getProperty("key2");
    test:assertEquals(key2Value, "value2");

    test:assertTrue(msgCtx.hasProperty("key1"));
    test:assertTrue(msgCtx.hasProperty("key2"));
    test:assertFalse(msgCtx.hasProperty("key3"));

    anydata removedValue = msgCtx.removeProperty("key1");
    test:assertFalse(msgCtx.hasProperty("key1"));
    test:assertEquals(removedValue, "value1");

    anydata|error nonExistentValue = trap msgCtx.getProperty("nonExistentKey");
    if nonExistentValue is anydata {
        test:assertFail("Expected error when accessing non-existent property");
    } else {
        test:assertEquals(nonExistentValue.message(), "Property with key 'nonExistentKey' not found");
    }

    anydata|error removedNonExistentValue = trap msgCtx.removeProperty("nonExistentKey");
    if removedNonExistentValue is anydata {
        test:assertFail("Expected error when removing non-existent property");
    } else {
        test:assertEquals(removedNonExistentValue.message(), "Property with key 'nonExistentKey' not found");
    }
}

@test:Config {
    groups: ["message_ctx_tests"]
}
function testMessageContextPropertyWithType() returns error? {
    MessageContext msgCtx = new (id = "12345", content = "Test message", handlerChainName = "testChain");
    msgCtx.setProperty("key1", "value1");
    msgCtx.setProperty("key2", 42);
    msgCtx.setProperty("key3", {"name": "Ballerina"});

    string key1Value = check msgCtx.getPropertyWithType("key1", string);
    test:assertEquals(key1Value, "value1");

    int key2Value = check msgCtx.getPropertyWithType("key2", int);
    test:assertEquals(key2Value, 42);

    map<string> key3Value = check msgCtx.getPropertyWithType("key3");
    test:assertEquals(key3Value["name"], "Ballerina");

    error|anydata nonExistentValue = trap msgCtx.getPropertyWithType("nonExistentKey", string);
    if nonExistentValue is error {
        test:assertEquals(nonExistentValue.message(), "Property with key 'nonExistentKey' not found");
    } else {
        test:assertFail("Expected error when accessing non-existent property with type");
    }
}

@test:Config {
    groups: ["message_ctx_tests"]
}
function testMessageContextDestinationSkip() {
    MessageContext msgCtx = new (id = "12345", content = "Test message", handlerChainName = "testChain");
    test:assertFalse(msgCtx.isDestinationSkipped("destination1"));
    msgCtx.skipDestination("destination1");
    test:assertTrue(msgCtx.isDestinationSkipped("destination1"));
    test:assertFalse(msgCtx.isDestinationSkipped("destination2"));
}

@test:Config {
    groups: ["message_ctx_tests"]
}
function testMessageContextErrors() {
    MessageContext msgCtx = new (id = "12345", content = "Test message", handlerChainName = "testChain");
    test:assertEquals(msgCtx.toRecord().errorMsg, ());

    msgCtx.setErrorMessage("An error occurred");
    test:assertEquals(msgCtx.toRecord().errorMsg, "An error occurred");

    error err = error("Test error");
    msgCtx.addDestinationError("handler1", err);
    map<ErrorInfo>? destinationErrors = msgCtx.toRecord().destinationErrors;
    if destinationErrors is () {
        test:assertFail("Expected destinationErrors to be set after adding an error");
    }
    test:assertTrue(destinationErrors.hasKey("handler1"));
    ErrorInfo errorInfo = destinationErrors.get("handler1");
    test:assertEquals(errorInfo.message, "Test error");
    test:assertEquals(errorInfo.detail, {});

    error newErr = error("Another test error", id = "err123", info = "Additional info");
    msgCtx.addDestinationError("handler2", newErr);
    destinationErrors = msgCtx.toRecord().destinationErrors;
    if destinationErrors is () {
        test:assertFail("Expected destinationErrors to be set after adding another error");
    }
    test:assertTrue(destinationErrors.hasKey("handler2"));
    ErrorInfo anotherErrorInfo = destinationErrors.get("handler2");
    test:assertEquals(anotherErrorInfo.message, "Another test error");
    test:assertTrue(anotherErrorInfo.detail.hasKey("info"));
    test:assertEquals(anotherErrorInfo.detail["info"], "Additional info");
    test:assertTrue(anotherErrorInfo.detail.hasKey("id"));
    test:assertEquals(anotherErrorInfo.detail["id"], "err123");

    msgCtx.cleanMessageForReplay();
    test:assertEquals(msgCtx.toRecord().destinationErrors, ());
    test:assertEquals(msgCtx.toRecord().errorMsg, ());
    test:assertEquals(msgCtx.toRecord().errorStackTrace, ());
    test:assertEquals(msgCtx.toRecord().errorDetails, ());
}
