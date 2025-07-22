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
