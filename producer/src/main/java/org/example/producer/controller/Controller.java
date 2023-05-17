package org.example.producer.controller;

import java.util.Map;
import java.util.stream.IntStream;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.example.producer.jms.MessageProducer;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
@Slf4j
public class Controller {

  private final MessageProducer producer;

  @GetMapping(path = "/send-messages-1")
  @ResponseStatus(code = HttpStatus.OK)
  public Map<String, String> produceMessages1() {
    log.info("Enter produceMessages1");
    IntStream.rangeClosed(1, 10)
        .forEach(value -> producer.queue1());
    return Map.of("message", "Messages sent successfully");
  }

  @GetMapping(path = "/send-messages-2")
  @ResponseStatus(code = HttpStatus.OK)
  public Map<String, String> produceMessages2() {
    log.info("Enter produceMessages2");
    IntStream.rangeClosed(1, 10)
        .forEach(value -> producer.queue2());
    return Map.of("message", "Messages sent successfully");
  }
}
