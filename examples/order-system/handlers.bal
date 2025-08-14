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
import ballerina/http;

import xlibb/pipeline;

@pipeline:ProcessorConfig {id: "validate_order"}
isolated function validateOrder(pipeline:MessageContext msgCtx) returns error? {
    Order 'order = check msgCtx.getContentWithType();
    Order _ = check constraint:validate('order);
}

@pipeline:FilterConfig {id: "filter_pending_orders"}
isolated function orderFilter(pipeline:MessageContext msgCtx) returns boolean|error {
    Order 'order = check msgCtx.getContentWithType();
    return 'order.status == PENDING || 'order.status == APPROVED;
}

@pipeline:TransformerConfig {id: "calculate_amount"}
isolated function calculateOrderAmount(pipeline:MessageContext msgCtx) returns CalculatedOrder|error {
    Order 'order = check msgCtx.getContentWithType();
    return {
        ...'order,
        amount: 'order.unitPrice * 'order.quantity
    };
}

@pipeline:TransformerConfig {id: "approve_order"}
isolated function approveOrder(pipeline:MessageContext msgCtx) returns CalculatedOrder|error {
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

@pipeline:ProcessorConfig {id: "get_discount"}
isolated function checkForOrderDiscount(pipeline:MessageContext msgCtx) returns error? {
    CalculatedOrder 'order = check msgCtx.getContentWithType();
    http:Client discountService = check new ("http://discount-service:8080");
    float discount = check discountService->/discounts/['order.customerId];
    msgCtx.setProperty("discount", discount);
}

@pipeline:TransformerConfig {id: "apply_discount"}
isolated function applyOrderDiscount(pipeline:MessageContext msgCtx) returns CalculatedOrder|error {
    CalculatedOrder 'order = check msgCtx.getContentWithType();
    decimal discount = check msgCtx.getPropertyWithType("discount");
    'order.amount = 'order.amount - ('order.amount * discount);
    return 'order;
}

@pipeline:DestinationConfig {
    id: "add_order_to_inventory",
    retryConfig: {
        maxRetries: 4,
        retryInterval: 2
    }
}
isolated function addOrderToInventory(pipeline:MessageContext msgCtx) returns json|error {
    CalculatedOrder 'order = check msgCtx.getContentWithType();
    http:Client inventoryService = check new ("http://inventory-service:8080");
    return inventoryService->/orders.post('order);
}
