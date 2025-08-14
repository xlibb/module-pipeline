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

import ballerina/constraint;
import ballerina/messaging;
import ballerina/random;
import ballerina/test;

isolated table<CalculatedOrder> key(id) ordersTable = table [];

public enum OrderStatus {
    PENDING,
    APPROVED,
    COMPLETED,
    FAILED
}

public type Order record {|
    @constraint:String {
        pattern: {
            value: re `^OR[0-9]{5}$`,
            message: "Order ID must start with 'OR' followed by 5 digits"
        }
    }
    readonly string id;
    @constraint:String {
        pattern: {
            value: re `^[a-zA-Z0-9]+$`,
            message: "Customer ID must be alphanumeric"
        }
    }
    readonly string customerId;
    @constraint:Number {
        minValue: {
            value: 0.0d,
            message: "Unit price must be a non-negative number"
        }
    }
    decimal unitPrice;
    @constraint:Int {
        minValue: {
            value: 1,
            message: "Quantity must be at least 1"
        }
    }
    int quantity;
    OrderStatus status;
|};

public type CalculatedOrder record {|
    *Order;
    decimal amount;
|};

@ProcessorConfig {
    id: "validate_order"
}
isolated function validateOrder(MessageContext msgCtx) returns error? {
    Order 'order = check msgCtx.getContentWithType();
    Order _ = check constraint:validate('order);
}

@FilterConfig {
    id: "filter_pending_orders"
}
isolated function orderFilter(MessageContext msgCtx) returns boolean|error {
    Order 'order = check msgCtx.getContentWithType();
    return 'order.status == PENDING || 'order.status == APPROVED;
}

@TransformerConfig {
    id: "calculate_amount"
}
isolated function calculateOrderAmount(MessageContext msgCtx) returns CalculatedOrder|error {
    Order 'order = check msgCtx.getContentWithType();
    return {
        ...'order,
        amount: 'order.unitPrice * 'order.quantity
    };
}

@TransformerConfig {
    id: "approve_order"
}
isolated function approveOrder(MessageContext msgCtx) returns CalculatedOrder|error {
    CalculatedOrder 'order = check msgCtx.getContentWithType();
    if 'order.status == APPROVED {
        return 'order; // Skip further processing if already approved
    }
    if 'order.amount > 100000.0d {
        'order.status = FAILED;
        return error("Order amount exceeds limit");
    }
    'order.status = APPROVED;
    return 'order;
}

@ProcessorConfig {
    id: "get_discount"
}
isolated function checkForOrderDiscount(MessageContext msgCtx) {
    float discount = random:createDecimal() * 0.1; // Random discount between 0 and 10%
    msgCtx.setProperty("discount", discount);
}

@TransformerConfig {
    id: "apply_discount"
}
isolated function applyOrderDiscount(MessageContext msgCtx) returns CalculatedOrder|error {
    CalculatedOrder 'order = check msgCtx.getContentWithType();
    decimal discount = check msgCtx.getPropertyWithType("discount");
    'order.amount = 'order.amount - ('order.amount * discount);
    return 'order;
}

@DestinationConfig {
    id: "add_order_to_table"
}
isolated function addOrderToTable(MessageContext msgCtx) returns string|error? {
    CalculatedOrder 'order = check msgCtx.getContentWithType();
    lock {
        if ordersTable.hasKey('order.id) {
            return error("Order already exists in the table");
        }
    }
    'order.status = COMPLETED;
    lock {
        ordersTable.add('order.clone());
    }
    return "Order added to table successfully";
}

type OrderMessage record {|
    *Message;
    Order content;
|};

type OrderFailureStoreMessage record {|
    readonly string orderId;
    OrderMessage msg;
    boolean inFlight = false;
|};

isolated client class OrderFailureStore {
    *messaging:Store;

    private table<OrderFailureStoreMessage> key(orderId) messagesTable = table [];

    isolated remote function store(anydata payload) returns error? {
        OrderMessage message = check payload.toJson().fromJsonWithType();
        lock {
            self.messagesTable.add({
                orderId: message.content.id,
                msg: message.clone(),
                inFlight: false
            });
        }
    }

    isolated remote function retrieveWithOrderId(string id) returns Order|error {
        lock {
            if self.messagesTable.hasKey(id) {
                return self.messagesTable.get(id).msg.content.clone();
            }
        }
        return error("Message not found with ID: " + id);
    }

    isolated remote function retrieve() returns messaging:Message|error? {
        lock {
            OrderFailureStoreMessage[] result = from var message in self.messagesTable
                where !message.inFlight
                limit 1
                select message;
            if result.length() == 0 {
                return;
            }
            result[0].inFlight = true;
            return {
                id: result[0].orderId,
                payload: result[0].msg.clone()
            };
        }
    }

    isolated remote function acknowledge(string id, boolean success) returns error? {
        lock {
            OrderFailureStoreMessage[] result = from var message in self.messagesTable
                where message.orderId == id && message.inFlight
                select message;
            if result.length() == 0 {
                return error(string `Message with ID '${id}' not found or not in flight`);
            }
            if success {
                _ = self.messagesTable.remove(result[0].orderId);
            } else {
                result[0].inFlight = false;
            }
        }
        return;
    }
}

final OrderFailureStore orderFailureStore = new;

HandlerChain orderHandlerChain = check new (
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
    failureStore = orderFailureStore
);

@test:Config {
    groups: ["handlerChainTests"]
}
function testHandlerChainUtils() {
    test:assertEquals(orderHandlerChain.getName(), "orderHandlerChain");
    test:assertExactEquals(orderHandlerChain.getFailureStore(), orderFailureStore);
}

@test:Config {
    groups: ["handlerChainTests"]
}
function testHandlerChainExecutionSuccess() returns error? {
    Order 'order = {
        id: "OR00001",
        customerId: "customer1",
        unitPrice: 100.0d,
        quantity: 2,
        status: PENDING
    };
    check assertOrderSuccess('order);

    Order 'order2 = {
        id: "OR00002",
        customerId: "customer2",
        unitPrice: 50000.0d,
        quantity: 300,
        status: APPROVED
    };
    check assertOrderSuccess('order2);

    Order 'order3 = {
        id: "OR00003",
        customerId: "customer3",
        unitPrice: 100.0d,
        quantity: 50,
        status: COMPLETED
    };
    check assertSkippedOrder('order3);
}

function assertSkippedOrder(Order 'order) returns error? {
    ExecutionSuccess executeResult = check orderHandlerChain.execute('order);
    map<any> destinationResults = executeResult.destinationResults;
    test:assertEquals(destinationResults, {});
    lock {
        test:assertFalse(ordersTable.hasKey('order.id));
    }
}

function assertOrderSuccess(Order 'order) returns error? {
    ExecutionSuccess executeResult = check orderHandlerChain.execute('order);
    map<any> destinationResults = executeResult.destinationResults;
    test:assertEquals(destinationResults, {
                                              "add_order_to_table": "Order added to table successfully"
                                          });
    lock {
        test:assertTrue(ordersTable.hasKey('order.id));
        CalculatedOrder addedOrder = ordersTable.get('order.id);
        test:assertEquals(addedOrder.id, 'order.id);
        test:assertEquals(addedOrder.customerId, 'order.customerId);
        test:assertEquals(addedOrder.unitPrice, 'order.unitPrice);
        test:assertEquals(addedOrder.quantity, 'order.quantity);
        test:assertEquals(addedOrder.status, COMPLETED);
        test:assertTrue(addedOrder.amount > 0.0d);
    }
}

@test:Config {
    groups: ["handlerChainTests"]
}
function testHandlerChainExecutionValidationFailure() returns error? {
    Order 'order = {
        id: "OR00004",
        customerId: "customer4",
        unitPrice: -50.0d, // Invalid unit price
        quantity: 1,
        status: PENDING
    };
    ExecutionSuccess|ExecutionError executeResult = orderHandlerChain.execute('order);
    if executeResult is ExecutionSuccess {
        test:assertFail("Expected execution to fail due to validation error, but it succeeded");
    }
    test:assertEquals(executeResult.message(), "Failed to execute processor: validate_order - Unit price must be a non-negative number.");

    Order|error failedOrder = orderFailureStore->retrieveWithOrderId('order.id);
    if failedOrder is error {
        test:assertFail("Failed order should be present in the failure store, but it was not found");
    }
    test:assertEquals(failedOrder, 'order);
}

@test:Config {
    groups: ["handlerChainTests"]
}
function testHandlerChainExecutionApprovalFailure() returns error? {
    Order 'order = {
        id: "OR00005",
        customerId: "customer5",
        unitPrice: 100.0d,
        quantity: 2000, // Exceeds approval limit
        status: PENDING
    };
    ExecutionSuccess|ExecutionError executeResult = orderHandlerChain.execute('order);
    if executeResult is ExecutionSuccess {
        test:assertFail("Expected execution to fail due to approval error, but it succeeded");
    }
    test:assertEquals(executeResult.message(), "Failed to execute processor: approve_order - Order amount exceeds limit");

    Order|error failedOrder = orderFailureStore->retrieveWithOrderId('order.id);
    if failedOrder is error {
        test:assertFail("Failed order should be present in the failure store, but it was not found");
    }
    test:assertEquals(failedOrder, 'order);

    failedOrder.status = APPROVED;
    check assertOrderSuccess(failedOrder);
}

@test:Config {
    groups: ["handlerChainTests"]
}
function testHandlerChainExecutionDestinationFailure() returns error? {
    Order 'order = {
        id: "OR00006",
        customerId: "customer6",
        unitPrice: 100.0d,
        quantity: 1,
        status: PENDING
    };
    check assertOrderSuccess('order);

    ExecutionSuccess|ExecutionError executeResult = orderHandlerChain.execute('order);
    if executeResult is ExecutionSuccess {
        test:assertFail("Expected execution to fail due to destination error, but it succeeded");
    }
    test:assertEquals(executeResult.message(), "Failed to execute destination: add_order_to_table - Order already exists in the table");

    Order|error failedOrder = orderFailureStore->retrieveWithOrderId('order.id);
    if failedOrder is error {
        test:assertFail("Failed order should be present in the failure store, but it was" +
                " not found");
    }
    test:assertEquals(failedOrder, 'order);

    lock {
        _ = ordersTable.remove('order.id);
    }
    check assertOrderSuccess('order);
}
