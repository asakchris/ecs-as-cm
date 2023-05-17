package org.example.producer.jms;

import java.time.LocalDateTime;
import javax.jms.Queue;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.jms.core.JmsTemplate;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
@Slf4j
public class MessageProducer {
  @Qualifier("queueOne")
  private final Queue queueOne;

  @Qualifier("queueOne")
  private final Queue queueTwo;

  private final JmsTemplate jmsTemplate;

  public void queue1() {
    log.info("Queue 1 producer started");
    String message = "Message generated at " + LocalDateTime.now();
    jmsTemplate.convertAndSend(queueOne, message);
    log.info("Queue 1 producer completed");
  }

  public void queue2() {
    log.info("Queue 2 producer started");
    String message = "Message generated at " + LocalDateTime.now();
    jmsTemplate.convertAndSend(queueTwo, message);
    log.info("Queue 2 producer completed");
  }
}
