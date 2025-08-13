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

# Represents the status of an order.
public enum OrderStatus {
    PENDING,
    APPROVED,
    COMPLETED,
    FAILED
}

public type Order record {|
    # Represents the unique identifier for the order.
    @constraint:String {pattern: re `^OR[0-9]{5}$`}
    readonly string id;
    # Represents the unique identifier for the customer who placed the order.
    @constraint:String {pattern:  re `^[a-zA-Z0-9]+$`}
    readonly string customerId;
    # Represents the item code
    @constraint:String {pattern: re `^[A-Z]{3}-[0-9]{4}$`}
    readonly string itemCode;
    # Represents the unit price of the item in the order.
    @constraint:Number {minValue: 0.0d}
    decimal unitPrice;
    # Represents the quantity of items in the order.
    @constraint:Int {minValue:  1}
    int quantity;
    # Represents the total price of the order.
    OrderStatus status;
|};

# Represents a calculated order that includes the total amount.
public type CalculatedOrder record {|
    *Order;
    # Represents the total amount for the order, calculated as unitPrice * quantity.
    decimal amount;
|};
