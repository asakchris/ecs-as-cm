package org.example.producer.jms;

import javax.jms.Queue;
import org.apache.activemq.command.ActiveMQQueue;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class JmsConfig {
  @Bean("queueOne")
  public Queue queueOne(@Value("${app.queues.test-1.name}") String queue) {
    return new ActiveMQQueue(queue);
  }
}
