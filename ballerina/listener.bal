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

import ballerina/lang.runtime;
import ballerina/log;
import ballerina/messaging;

isolated function startReplayListener(HandlerChain handlerChain, ReplayListenerConfiguration config) returns Error? {
    ReplayListenerConfiguration {replayStore, ...listenerConfig} = config;
    messaging:Store targetStore = replayStore ?: handlerChain.getFailureStore();
    do {
        messaging:StoreListenerConfiguration replayListenerConfig = {
            pollingInterval: listenerConfig.pollingInterval,
            ackWithFailureAfterMaxRetries: false,
            // Retry logic is handled in the service where we use the updated message to resume
            maxRetries: 0
            // Dead letter store should store the updated message, so this is handled by the service
        };
        messaging:StoreListener replayListener = check new (targetStore, replayListenerConfig);
        ReplayService replayService = new (handlerChain, listenerConfig.deadLetterStore, maxRetries = listenerConfig.maxRetries, retryInterval = listenerConfig.retryInterval);
        check replayListener.attach(replayService);
        check replayListener.'start();
        runtime:registerListener(replayListener);
        log:printInfo("replay listener started successfully", handlerchain = handlerChain.getName());
    } on fail error err {
        return error Error("Failed to start replay listener", err);
    }
}

# Retry configuration for the replay service.
public type ServiceRetryConfiguration record {|
    # The maximum number of retries to attempt for a message
    int maxRetries = 3;
    # The interval in seconds to wait before retrying a message
    decimal retryInterval = 1;
|};

isolated service class ReplayService {
    *messaging:StoreService;

    private final HandlerChain handlerChain;
    private final readonly & ServiceRetryConfiguration config;
    private final messaging:Store deadLetterStore;

    isolated function init(HandlerChain handlerChain, messaging:Store deadLetterStore, *ServiceRetryConfiguration config) {
        self.handlerChain = handlerChain;
        self.config = config.cloneReadOnly();
        self.deadLetterStore = deadLetterStore;
    }

    isolated remote function onMessage(anydata message) returns error? {
        Message|error replayableMessage = message.toJson().fromJsonWithType();
        if replayableMessage is error {
            log:printError("error converting message to replayable message type", replayableMessage,
                    handlerchain = self.handlerChain.getName());
            return replayableMessage;
        }

        ExecutionSuccess|ExecutionError executionResult = self.handlerChain.replay(replayableMessage);
        if executionResult is ExecutionSuccess {
            log:printDebug("message execution replayed successfully", msgId = executionResult.message.id,
                    handlerchain = self.handlerChain.getName());
            return;
        }

        Message updatedReplayableMessage = check executionResult.detail().message.toJson().fromJsonWithType();
        foreach int attempt in 1 ... self.config.maxRetries {
            log:printDebug("retrying message execution replay", retryAttempt = attempt, msgId = updatedReplayableMessage.id,
                    handlerchain = self.handlerChain.getName());
            ExecutionSuccess|ExecutionError executionResultOnRetry = self.handlerChain.replay(updatedReplayableMessage);
            if executionResultOnRetry is ExecutionSuccess {
                log:printDebug("message execution replayed successfully", msgId = updatedReplayableMessage.id,
                        handlerchain = self.handlerChain.getName());
                return;
            }
            updatedReplayableMessage = check executionResultOnRetry.detail().message.toJson().fromJsonWithType();
            if attempt < self.config.maxRetries {
                runtime:sleep(self.config.retryInterval);
            }
        }

        string msgId = updatedReplayableMessage.id;
        log:printError("failed to replay message execution after maximum retries", executionResult, msgId = msgId,
                handlerchain = self.handlerChain.getName());

        error? dlsResult = check self.deadLetterStore->store(updatedReplayableMessage);
        if dlsResult is error {
            log:printError("failed to store message in dead letter store", dlsResult, msgId = msgId,
                    handlerchain = self.handlerChain.getName());
            return error("Failed to store message in dead letter store", dlsResult);
        }
        log:printDebug("message stored in dead letter store after maximum retries", msgId = msgId,
                handlerchain = self.handlerChain.getName());
    }
}
