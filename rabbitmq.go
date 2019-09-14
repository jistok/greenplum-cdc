// This example declares a durable Exchange, an ephemeral (auto-delete) Queue,
// binds the Queue to the Exchange with a binding key, and consumes every
// message published to that Exchange with that routing key.
//
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"regexp"
	"time"

	"github.com/streadway/amqp"
)

/* TODO:
- Only ACK at the end, for all messages, if there are no errors.
- Add a max. T value, to limit the duration of a single load operation.
*/

var (
	uri          = flag.String("uri", "amqp://guest:guest@localhost:5672/", "AMQP URI")
	exchange     = flag.String("exchange", "test-exchange", "Durable, non-auto-deleted AMQP exchange name")
	exchangeType = flag.String("exchange-type", "direct", "Exchange type - direct|fanout|topic|x-custom")
	queue        = flag.String("queue", "test-queue", "Ephemeral AMQP queue name")
	bindingKey   = flag.String("key", "test-key", "AMQP binding key")
	consumerTag  = flag.String("consumer-tag", "simple-consumer", "AMQP consumer tag (should not be blank)")
	lifetime     = flag.Duration("lifetime", 100*time.Millisecond, "Max. time to wait for data, ms (default: 100ms)")
)

// Holds most recent Delivery, so it can be Ack'd
var lastDelivery amqp.Delivery

// When did we handle the last delivery?
var timeOfLastDelivery time.Time = time.Now()

var re = regexp.MustCompile(`[\t\r\n]+`)

var tSleep time.Duration = 100 * time.Millisecond

func init() {
	flag.Parse()
}

func main() {

	c, err := NewConsumer(*uri, *exchange, *exchangeType, *queue, *bindingKey, *consumerTag)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s\n", err)
		os.Exit(1)
	}

	for timeOfLastDelivery = time.Now(); time.Now().Sub(timeOfLastDelivery).Seconds() <= (*lifetime).Seconds(); {
		fmt.Fprintf(os.Stderr, "Sleeping %v ...\n", tSleep)
		time.Sleep(tSleep)
	}

	// Ack all deliveries
	lastDelivery.Ack(true)

	if err := c.Shutdown(); err != nil {
		fmt.Fprintf(os.Stderr, "error during shutdown: %s\n", err)
		os.Exit(1)
	}

}

type Consumer struct {
	conn    *amqp.Connection
	channel *amqp.Channel
	tag     string
	done    chan error
}

func NewConsumer(amqpURI, exchange, exchangeType, queueName, key, ctag string) (*Consumer, error) {
	c := &Consumer{
		conn:    nil,
		channel: nil,
		tag:     ctag,
		done:    make(chan error),
	}

	var err error

	log.Printf("dialing %q", amqpURI)
	c.conn, err = amqp.Dial(amqpURI)
	if err != nil {
		return nil, fmt.Errorf("Dial: %s", err)
	}

	go func() {
		fmt.Fprintf(os.Stderr, "closing: %s\n", <-c.conn.NotifyClose(make(chan *amqp.Error)))
	}()

	fmt.Fprintf(os.Stderr, "got Connection, getting Channel\n")
	c.channel, err = c.conn.Channel()
	if err != nil {
		return nil, fmt.Errorf("Channel: %s", err)
	}

	fmt.Fprintf(os.Stderr, "got Channel, declaring Exchange (%q)\n", exchange)
	if err = c.channel.ExchangeDeclare(
		exchange,     // name of the exchange
		exchangeType, // type
		true,         // durable
		false,        // delete when complete
		false,        // internal
		false,        // noWait
		nil,          // arguments
	); err != nil {
		return nil, fmt.Errorf("Exchange Declare: %s", err)
	}

	fmt.Fprintf(os.Stderr, "declared Exchange, declaring Queue %q\n", queueName)
	queue, err := c.channel.QueueDeclare(
		queueName, // name of the queue
		true,      // durable
		false,     // delete when unused
		false,     // exclusive
		false,     // noWait
		nil,       // arguments
	)
	if err != nil {
		return nil, fmt.Errorf("Queue Declare: %s", err)
	}

	fmt.Fprintf(os.Stderr, "declared Queue (%q %d messages, %d consumers), binding to Exchange (key %q)\n",
		queue.Name, queue.Messages, queue.Consumers, key)

	if err = c.channel.QueueBind(
		queue.Name, // name of the queue
		key,        // bindingKey
		exchange,   // sourceExchange
		false,      // noWait
		nil,        // arguments
	); err != nil {
		return nil, fmt.Errorf("Queue Bind: %s", err)
	}

	fmt.Fprintf(os.Stderr, "Queue bound to Exchange, starting Consume (consumer tag %q)\n", c.tag)
	deliveries, err := c.channel.Consume(
		queue.Name, // name
		c.tag,      // consumerTag,
		false,      // noAck
		false,      // exclusive
		false,      // noLocal
		false,      // noWait
		nil,        // arguments
	)
	if err != nil {
		return nil, fmt.Errorf("Queue Consume: %s", err)
	}

	go handle(deliveries, c.done)

	return c, nil
}

func (c *Consumer) Shutdown() error {
	// will close() the deliveries channel
	if err := c.channel.Cancel(c.tag, true); err != nil {
		return fmt.Errorf("Consumer cancel failed: %s", err)
	}

	if err := c.conn.Close(); err != nil {
		return fmt.Errorf("AMQP connection close error: %s", err)
	}

	defer fmt.Fprintf(os.Stderr, "AMQP shutdown OK\n")

	// wait for handle() to exit
	return <-c.done
}

func handle(deliveries <-chan amqp.Delivery, done chan error) {
	for d := range deliveries {
		fmt.Printf(
			"%s\n",
			re.ReplaceAllString(string(d.Body), " "), // Replace TAB, CR, NL with space
		)
		lastDelivery = d
		timeOfLastDelivery = time.Now()
	}
	fmt.Fprintf(os.Stderr, "handle: deliveries channel closed\n")
	done <- nil
}
