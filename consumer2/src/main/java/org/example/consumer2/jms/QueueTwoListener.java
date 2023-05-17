package org.example.consumer2.jms;

import static org.example.consumer2.util.Utils.run;

import lombok.AllArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jms.annotation.JmsListener;
import org.springframework.stereotype.Component;

@Component
@Slf4j
@AllArgsConstructor
public class QueueTwoListener {
  @JmsListener(
      destination = "${app.queues.test-2.name}",
      concurrency = "${app.queues.test-2.concurrency}")
  public void onMessage(String message) {
    log.info("Message received: {}", message);
    run(1);
    log.info("Message processed: {}", message);
  }
}
