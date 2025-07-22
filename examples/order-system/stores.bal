import ballerinax/rabbitmq;

# RabbitMQ queue to store the failed orders.
final rabbitmq:MessageStore failureStore = check new("order-failure-store");

# RabbitMQ queue to store the dead-lettered orders.
final rabbitmq:MessageStore deadLetterStore = check new("order-dead-letter-store");

# RabbitMQ queue to trigger the replay of failed orders.
final rabbitmq:MessageStore replayStore = check new("order-replay-store");
