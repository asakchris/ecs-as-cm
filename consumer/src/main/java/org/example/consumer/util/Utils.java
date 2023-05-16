package org.example.consumer.util;

import java.time.LocalDateTime;

public class Utils {
  public static void run(int minutes){
    final LocalDateTime nowPlusMin = LocalDateTime.now().plusMinutes(minutes);
    while (nowPlusMin.isAfter(LocalDateTime.now())) {
      // Run the loop for n minutes
    }
  }
}
