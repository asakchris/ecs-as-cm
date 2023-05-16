package org.example.consumer.jms;

import static org.example.consumer.util.Utils.run;

import lombok.AllArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jms.annotation.JmsListener;
import org.springframework.stereotype.Component;

@Component
@Slf4j
@AllArgsConstructor
public class QueueOneListener {
  @JmsListener(
      destination = "${app.queues.test-1.name}",
      concurrency = "${app.queues.test-1.concurrency}")
  public void onMessage(String message) {
    log.info("Message received: {}", message);
    run(1);
    log.info("Message processed: {}", message);
  }
}
