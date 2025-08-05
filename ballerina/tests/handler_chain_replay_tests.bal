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
import ballerina/messaging;
import ballerina/test;

final OrderFailureStore failureStore = new;
final OrderFailureStore deadLetterStore = new;
final messaging:InMemoryMessageStore replayStore = new;

HandlerChain orderReplayableHandlerChain = check new (
    name = "orderHandlerChain",
    processors = [
        validateOrder,
        orderFilter,
        calculateOrderAmount,
        approveOrder,
        checkForOrderDiscount,
        applyOrderDiscount
    ],
    destinations = addOrderToTable,
    failureStore = failureStore,
    replayListenerConfig = {
        deadLetterStore: deadLetterStore,
        replayStore: replayStore,
        pollingInterval: 4
    }
);

@test:Config {
    groups: ["handlerChainReplayTests"]
}
function testHandlerChainReplayWithEdit() returns error? {
    Order 'order = {
        id: "OR10001",
        customerId: "customer5",
        unitPrice: 100.0d,
        quantity: 2000, // Exceeds approval limit
        status: PENDING
    };
    ExecutionSuccess|error result = orderReplayableHandlerChain.execute('order);
    if result is ExecutionSuccess {
        test:assertFail("Expected failure due to order exceeding approval limit, but got success");
    }

    messaging:Message|error? failedOrderMessage = failureStore->retrieve();
    if failedOrderMessage is error? {
        test:assertFail("Failed order should be present in the failure store, but it was not found");
    }
    OrderMessage failedOrder = check failedOrderMessage.payload.toJson().fromJsonWithType();
    test:assertEquals(failedOrder.content, 'order);

    failedOrder.content.status = "APPROVED"; // Fixing the status
    replayStore->store(failedOrder);

    check failureStore->acknowledge(failedOrderMessage.id, true);

    runtime:sleep(5); // Wait for the replay to process

    messaging:Message|error? replayedOrderMessage = replayStore->retrieve();
    if replayedOrderMessage is messaging:Message {
        test:assertFail("Replay store should be empty after successful replay, but found a message");
    }
    lock {
        test:assertTrue(ordersTable.hasKey('order.id));
    }
}

@test:Config {
    groups: ["handlerChainReplayTests"],
    dependsOn: [testHandlerChainReplayWithEdit]
}
function testHandlerChainReplayWithoutEdit() returns error? {
    Order 'order = {
        id: "OR10001",
        customerId: "customer5",
        unitPrice: 10.0d,
        quantity: 2,
        status: PENDING
    };
    ExecutionSuccess|error result = orderReplayableHandlerChain.execute('order);
    if result is ExecutionSuccess {
        test:assertFail("Expected failure due to the same order existing in the table, but got success");
    }

    messaging:Message|error? failedOrderMessage = failureStore->retrieve();
    if failedOrderMessage is error? {
        test:assertFail("Failed order should be present in the failure store, but it was" +
                " not found");
    }
    OrderMessage failedOrder = check failedOrderMessage.payload.toJson().fromJsonWithType();
    test:assertEquals(failedOrder.content, 'order);

    lock {
        if ordersTable.hasKey('order.id) {
            _ = ordersTable.remove('order.id);
        }
    }

    replayStore->store(failedOrder);

    check failureStore->acknowledge(failedOrderMessage.id, true);

    runtime:sleep(5); // Wait for the replay to process

    messaging:Message|error? replayedOrderMessage = replayStore->retrieve();
    if replayedOrderMessage is messaging:Message {
        test:assertFail("Replay store should be empty after successful replay, but found a message");
    }
    lock {
        test:assertTrue(ordersTable.hasKey('order.id));
    }

    lock {
        test:assertTrue(ordersTable.hasKey('order.id));
    }
}

@test:Config {
    groups: ["handlerChainReplayTests"],
    dependsOn: [testHandlerChainReplayWithoutEdit]
}
function testHandlerChainReplayWithDeadLetterStore() returns error? {
    Order 'order = {
        id: "OR10001",
        customerId: "customer6",
        unitPrice: 100.0d,
        quantity: 2000,
        status: APPROVED
    };
    ExecutionSuccess|error result = orderReplayableHandlerChain.execute('order);
    if result is ExecutionSuccess {
        test:assertFail("Expected failure due to same order existing in the table, but got success");
    }

    messaging:Message|error? failedOrderMessage = failureStore->retrieve();
    if failedOrderMessage is error? {
        test:assertFail("Failed order should be present in the failure store, but it was" +
                " not found");
    }

    OrderMessage failedOrder = check failedOrderMessage.payload.toJson().fromJsonWithType();
    test:assertEquals(failedOrder.content, 'order);

    replayStore->store(failedOrder);

    check failureStore->acknowledge(failedOrderMessage.id, true);

    runtime:sleep(30); // Wait for the replay to process

    messaging:Message|error? replayedOrderMessage = replayStore->retrieve();
    if replayedOrderMessage is messaging:Message {
        test:assertFail("Replay store should be empty after dead lettering the message, but found a message");
    }

    messaging:Message|error? deadLetteredOrderMessage = deadLetterStore->retrieve();
    if deadLetteredOrderMessage is error? {
        test:assertFail("Dead letter store should contain the message after replay failure, but it" +
                " was not found");
    }
    OrderMessage deadLetteredOrder = check deadLetteredOrderMessage.payload.toJson().fromJsonWithType();
    test:assertEquals(deadLetteredOrder.content.id, 'order.id);
}
