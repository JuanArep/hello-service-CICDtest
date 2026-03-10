package com.example.demo;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

class HelloControllerTest {

  @Test
  void hello_returnsHello() {
    HelloController c = new HelloController();
    assertThat(c.hello()).isEqualTo("hello");
  }
}
