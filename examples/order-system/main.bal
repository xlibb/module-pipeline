import ballerina/http;

import xlibb/pipeline;

final pipeline:HandlerChain orderPipeline = check new (
    name = "orderPipeline",
    processors = [
        validateOrder,
        orderFilter,
        calculateOrderAmount,
        approveOrder,
        checkForOrderDiscount,
        applyOrderDiscount
    ],
    destinations = addOrderToInventory,
    failureStore = failureStore,
    replayListenerConfig = {
        pollingInterval: 5,
        maxRetries: 3,
        retryInterval: 2,
        deadLetterStore: deadLetterStore,
        replayStore: replayStore
    }
);

service /api/v1 on new http:Listener(8080) {

    resource function post orders(Order 'order) returns http:Accepted|error {
        _ = start orderPipeline.execute('order.clone());
        return http:ACCEPTED;
    }
}
