import ballerina/messaging;
import ballerina/lang.runtime;
import ballerina/log;

isolated function startResumeListener(Channel channel, ResumeListenerConfiguration config) returns Error? {
    ResumeListenerConfiguration {store, ...listenerConfig} = config;
    messaging:Store targetStore = store ?: channel.getStore();
    do {
        messaging:StoreListenerConfiguration resumeListenerConfig = {
            pollingInterval: listenerConfig.pollingInterval,
            dropMessageAfterMaxRetries: false,
            // Dead letter store should store the updated message, so this is handled by the service
            // Retry logic is handled in the service where we use the updated message to resume
            maxRetries: 0
        };
        messaging:StoreListener resumeListener = check new (targetStore, resumeListenerConfig);
        ReplayService replayService = new (channel, listenerConfig.deadLetterStore, maxRetries = listenerConfig.maxRetries, retryInterval = listenerConfig.retryInterval);
        check resumeListener.attach(replayService);
        check resumeListener.'start();
        runtime:registerListener(resumeListener);
        log:printInfo("resume listener started successfully", channel = channel.getName());
    } on fail error err {
        return error Error("Failed to start resume listener", err);
    }
}

type ServiceRetryConfiguration record {|
    int maxRetries = 3;
    decimal retryInterval = 1;
|};

isolated service class ReplayService {
    *messaging:StoreService;

    private final Channel channel;
    private final readonly & ServiceRetryConfiguration config;
    private final messaging:Store deadLetterStore;

    isolated function init(Channel channel, messaging:Store deadLetterStore, *ServiceRetryConfiguration config) {
        self.channel = channel;
        self.config = config.cloneReadOnly();
        self.deadLetterStore = deadLetterStore;
    }

    isolated remote function onMessage(anydata message) returns error? {
        Message|error resumableMessage = message.toJson().fromJsonWithType();
        if resumableMessage is error {
            log:printError("error converting message to resumable message type", 'error = resumableMessage);
            return resumableMessage;
        }

        ExecutionResult|ExecutionError executionResult = self.channel.resume(resumableMessage);
        if executionResult is ExecutionResult {
            log:printDebug("message execution resumed successfully", msgId = executionResult.message.id);
            return;
        }

        Message updatedResumableMessage = executionResult.detail().message;
        foreach int attempt in 1 ... self.config.maxRetries {
            ExecutionResult|ExecutionError executionResultOnRetry = self.channel.resume(updatedResumableMessage);
            if executionResultOnRetry is ExecutionResult {
                log:printDebug("message execution resumed successfully", msgId = updatedResumableMessage.id);
                return;
            }
            updatedResumableMessage = executionResultOnRetry.detail().message;
            if attempt < self.config.maxRetries {
                runtime:sleep(self.config.retryInterval);
            }
        }

        log:printError("failed to resume message execution after retries", msgId = updatedResumableMessage.id,
                'error = executionResult);
        do {
            check self.deadLetterStore->store(updatedResumableMessage);
            log:printDebug("message stored in dead letter store after retries", msgId = updatedResumableMessage.id);
        } on fail error err {
            log:printError("failed to store message in dead letter store", msgId = updatedResumableMessage.id, 'error = err);
            return error("Failed to store message in dead letter store", err);
        }
    }
}
