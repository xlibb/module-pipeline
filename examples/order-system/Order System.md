# Order system example

## Overview

This example demonstrates a comprehensive order processing pipeline using the Ballerina Pipeline module. It showcases how to build a resilient, fault-tolerant order management system that can handle order validation, processing, transformation, and reliable delivery to downstream systems.

The example implements a real-world scenario where orders submitted through an HTTP API are processed through a series of handlers, with built-in error handling, retry mechanisms, and dead letter queues for failed messages.

### Key components

The order system consists of the following main components:

- **Order Processing Pipeline**: A handler chain that processes orders through multiple stages
- **HTTP Service**: REST API endpoint for order submission
- **Message Processors**: Functions that validate, filter, transform, and enrich order data
- **Destination Handler**: Delivers processed orders to an external inventory service
- **Message Stores**: RabbitMQ-based stores for failure handling, replay, and dead letter queues
- **Retry and Replay Mechanisms**: Automatic retry and intelligent replay of failed messages

## Implementation

### Handlers

The order processing pipeline is composed of several types of handlers, each serving a specific purpose in the order processing workflow.

#### Processors

The system includes six different processors that handle various aspects of order processing:

**1. Order Validation (`validateOrder`)**

```ballerina
@pipeline:ProcessorConfig {id: "validate_order"}
isolated function validateOrder(pipeline:MessageContext msgCtx) returns error?
```

- **Type**: Processor
- **Purpose**: Validates the incoming order against defined constraints
- **Function**: Uses Ballerina's constraint validation to ensure order data integrity
- **Validation Rules**:
  - Order ID must match pattern `^OR[0-9]{5}$`
  - Customer ID must be alphanumeric
  - Item code must follow pattern `^[A-Z]{3}-[0-9]{4}$`
  - Unit price must be non-negative
  - Quantity must be at least 1

**2. Order Filter (`orderFilter`)**

```ballerina
@pipeline:FilterConfig {id: "filter_pending_orders"}
isolated function orderFilter(pipeline:MessageContext msgCtx) returns boolean|error
```

- **Type**: Filter
- **Purpose**: Filters orders to only process those in PENDING or APPROVED status
- **Function**: Returns `true` for orders that should continue processing, `false` for others

**3. Calculate Order Amount (`calculateOrderAmount`)**

```ballerina
@pipeline:TransformerConfig {id: "calculate_amount"}
isolated function calculateOrderAmount(pipeline:MessageContext msgCtx) returns CalculatedOrder|error
```

- **Type**: Transformer
- **Purpose**: Calculates the total amount for the order
- **Function**: Transforms `Order` to `CalculatedOrder` by computing `amount = unitPrice * quantity`

**4. Approve Order (`approveOrder`)**

```ballerina
@pipeline:TransformerConfig {id: "approve_order"}
isolated function approveOrder(pipeline:MessageContext msgCtx) returns CalculatedOrder|error
```

- **Type**: Transformer
- **Purpose**: Approves orders based on business rules
- **Business Logic**:
  - Skips processing if already approved
  - Rejects orders exceeding $100,000 limit
  - Sets status to APPROVED for valid orders

**5. Check Order Discount (`checkForOrderDiscount`)**

```ballerina
@pipeline:ProcessorConfig {id: "get_discount"}
isolated function checkForOrderDiscount(pipeline:MessageContext msgCtx) returns error?
```

- **Type**: Processor
- **Purpose**: Retrieves discount information from external discount service
- **Function**: Calls external service and stores discount in message context properties

**6. Apply Order Discount (`applyOrderDiscount`)**

```ballerina
@pipeline:TransformerConfig {id: "apply_discount"}
isolated function applyOrderDiscount(pipeline:MessageContext msgCtx) returns CalculatedOrder|error
```

- **Type**: Transformer
- **Purpose**: Applies the retrieved discount to the order amount
- **Function**: Reduces order amount by the calculated discount percentage

#### Destination

**Add Order to Inventory (`addOrderToInventory`)**

```ballerina
@pipeline:DestinationConfig {
        id: "add_order_to_inventory",
        retryConfig: {
                maxRetries: 4,
                retryInterval: 2
        }
}
isolated function addOrderToInventory(pipeline:MessageContext msgCtx) returns json|error
```

- **Type**: Destination
- **Purpose**: Delivers the processed order to an external inventory service
- **Retry Configuration**:
  - Maximum 4 retry attempts
  - 2-second interval between retries
- **Function**: Makes HTTP POST call to inventory service at `http://inventory-service:8080/orders`

### Message stores

The system uses three RabbitMQ-based message stores to handle different aspects of message reliability:

#### Failure store

```ballerina
final rabbitmq:MessageStore failureStore = check new("order-failure-store");
```

- **Purpose**: Stores messages that fail during processing or delivery
- **Queue**: `order-failure-store`
- **Usage**: Automatically populated when processors or destinations encounter errors

#### Replay store

```ballerina
final rabbitmq:MessageStore replayStore = check new("order-replay-store");
```

- **Purpose**: Triggers replay of failed messages
- **Queue**: `order-replay-store`
- **Usage**: Messages moved here initiate automatic replay attempts

#### Dead letter store

```ballerina
final rabbitmq:MessageStore deadLetterStore = check new("order-dead-letter-store");
```

- **Purpose**: Stores permanently failed messages after exhausting all retry attempts
- **Queue**: `order-dead-letter-store`
- **Usage**: Final destination for messages that cannot be processed successfully

### Handler chain

The order processing pipeline is orchestrated by a HandlerChain that manages the entire message flow:

```ballerina
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
```

**Configuration Details:**

- **Processors**: Executed sequentially in the defined order
- **Destinations**: Executed in parallel (single destination in this example)
- **Polling Interval**: 5 seconds between replay attempts
- **Max Retries**: 3 retry attempts for replay operations
- **Retry Interval**: 2 seconds between retry attempts

### Order service

The HTTP service provides a REST API endpoint for order submission:

```ballerina
service /api/v1 on new http:Listener(8080) {
        resource function post orders(Order 'order) returns http:Accepted|error {
                _ = start orderPipeline.execute('order.clone());
                return http:ACCEPTED;
        }
}
```

**Features:**

- **Endpoint**: `POST /api/v1/orders`
- **Port**: 8080
- **Asynchronous Processing**: Uses `start` keyword for non-blocking execution
- **Response**: Returns `HTTP 202 Accepted` immediately
- **Input**: Accepts `Order` record type with validation constraints

## Reliable delivery

The system implements multiple layers of reliability to ensure no orders are lost and all failures are handled gracefully:

### Destination level retry

- Each destination can be configured with its own retry policy
- The inventory destination retries up to 4 times with 2-second intervals
- Failures after exhausting retries are sent to the failure store

### Failure store integration

- All processing and delivery failures are automatically captured
- Original message content and context are preserved
- Enables debugging and analysis of failure patterns

### Automatic replay mechanism

- Replay listener polls replay stores every 5 seconds
- Failed messages are automatically reprocessed through the pipeline
- Intelligent replay skips successful destinations in multi-destination scenarios
- Maximum 3 replay attempts with 2-second intervals. Provides additional resilience for transient failures

### Dead letter store implementation

- Permanently failed messages are moved to dead letter store
- Prevents infinite retry loops
- Enables manual intervention and analysis
- Supports compliance and audit requirements

## Starting the order service

### Prerequisites

1. **Ballerina**: Ensure you have Ballerina installed on your system
2. **RabbitMQ Server**: A running RabbitMQ server instance for message stores
3. **External Services**: Mock or actual implementations of:
     - Discount service running on `http://discount-service:8080`
     - Inventory service running on `http://inventory-service:8080`

### Setup instructions

1. **Navigate to the project directory**:

     ```bash
     cd examples/order-system
     ```

2. **Start RabbitMQ server** (if not already running):

     ```bash
     # Using Docker
     docker run -d --name rabbitmq -p 5672:5672 -p 15672:15672 rabbitmq:3-management
     
     # Or using local installation
     rabbitmq-server
     ```

3. **Run the application**:

     ```bash
     bal run
     ```

     The service will start on port 8080 and be ready to accept order requests.

## Testing the services

### Submit an order

Send a POST request to submit a new order:

```bash
curl -X POST http://localhost:8080/api/v1/orders \
    -H "Content-Type: application/json" \
    -d '{
        "id": "OR12345",
        "customerId": "CUST001",
        "itemCode": "ABC-1234",
        "unitPrice": 25.99,
        "quantity": 2,
        "status": "PENDING"
    }'
```

### Expected response

```json
HTTP/1.1 202 Accepted
```

### Testing different scenarios

#### 1. Valid order processing

```bash
curl -X POST http://localhost:8080/api/v1/orders \
    -H "Content-Type: application/json" \
    -d '{
        "id": "OR12346",
        "customerId": "CUST002",
        "itemCode": "XYZ-5678",
        "unitPrice": 15.50,
        "quantity": 3,
        "status": "PENDING"
    }'
```

#### 2. Order exceeding limit (should fail)

```bash
curl -X POST http://localhost:8080/api/v1/orders \
    -H "Content-Type: application/json" \
    -d '{
        "id": "OR12347",
        "customerId": "CUST003",
        "itemCode": "LUX-9999",
        "unitPrice": 50000.00,
        "quantity": 3,
        "status": "PENDING"
    }'
```

#### 3. Invalid order format (should be filtered)

```bash
curl -X POST http://localhost:8080/api/v1/orders \
    -H "Content-Type: application/json" \
    -d '{
        "id": "INVALID",
        "customerId": "CUST004",
        "itemCode": "ABC-1234",
        "unitPrice": 10.00,
        "quantity": 1,
        "status": "PENDING"
    }'
```

### Monitoring

**Check RabbitMQ Management UI**:

- Access: <http://localhost:15672>
- Default credentials: guest/guest
- Monitor queues: `order-failure-store`, `order-replay-store`, `order-dead-letter-store`

**View Processing Logs**:
The application will log processing steps and any errors encountered during order processing.

## Key features demonstrated

1. **Sequential Processing Pipeline** - Messages flow through processors in defined order with automatic error handling
2. **Message Transformation** - Type-safe transformations with progressive message enrichment
3. **External Service Integration** - HTTP service calls with graceful failure handling and timeout management
4. **Comprehensive Error Handling** - Automatic failure capture with context preservation for debugging
5. **Intelligent Retry and Replay** - Configurable retry policies with smart replay mechanisms
6. **Dead Letter Queue Pattern** - Permanent storage for repeatedly failed messages preventing infinite loops
7. **Asynchronous Processing** - Non-blocking HTTP responses with background message processing
8. **Type Safety and Validation** - Strong typing with constraint-based validation ensuring data integrity

This example demonstrates how the Ballerina Pipeline module simplifies building enterprise-grade message processing systems with robust error handling, and retry mechanisms features.
