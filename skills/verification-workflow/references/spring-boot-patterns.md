# Spring Boot Test Patterns

## Dependencies (pom.xml)

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-test</artifactId>
    <scope>test</scope>
</dependency>
```

## Unit Tests (No Spring Context)

### Service Test

```java
// src/test/java/com/example/service/UserServiceSpec.java
package com.example.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UserServiceSpec {

    @Mock
    private UserRepository userRepository;

    private UserService userService;

    @BeforeEach
    void setUp() {
        userService = new UserService(userRepository);
    }

    @Test
    void findById_returnsUser_whenUserExists() {
        User expected = new User(1L, "john@example.com");
        when(userRepository.findById(1L)).thenReturn(Optional.of(expected));

        Optional<User> result = userService.findById(1L);

        assertThat(result).isPresent();
        assertThat(result.get().getEmail()).isEqualTo("john@example.com");
    }

    @Test
    void findById_returnsEmpty_whenUserNotFound() {
        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        Optional<User> result = userService.findById(99L);

        assertThat(result).isEmpty();
    }
}
```

### Validation Test

```java
@ExtendWith(MockitoExtension.class)
class UserValidatorSpec {

    private UserValidator validator = new UserValidator();

    @Test
    void validate_succeeds_withValidEmail() {
        UserRequest request = new UserRequest("user@example.com", "John");

        ValidationResult result = validator.validate(request);

        assertThat(result.isValid()).isTrue();
    }

    @Test
    void validate_fails_withInvalidEmail() {
        UserRequest request = new UserRequest("invalid-email", "John");

        ValidationResult result = validator.validate(request);

        assertThat(result.isValid()).isFalse();
        assertThat(result.getErrors()).contains("Invalid email format");
    }
}
```

## Integration Tests (With Spring Context)

### Controller Test with MockMvc

```java
// src/test/java/com/example/controller/UserControllerSpec.java
@WebMvcTest(UserController.class)
class UserControllerSpec {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private UserService userService;

    @Test
    void getUser_returns200_whenUserExists() throws Exception {
        User user = new User(1L, "john@example.com");
        when(userService.findById(1L)).thenReturn(Optional.of(user));

        mockMvc.perform(get("/api/users/1"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.email").value("john@example.com"));
    }

    @Test
    void getUser_returns404_whenUserNotFound() throws Exception {
        when(userService.findById(99L)).thenReturn(Optional.empty());

        mockMvc.perform(get("/api/users/99"))
            .andExpect(status().isNotFound());
    }

    @Test
    void createUser_returns201_withValidRequest() throws Exception {
        User created = new User(1L, "new@example.com");
        when(userService.create(any())).thenReturn(created);

        mockMvc.perform(post("/api/users")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"email": "new@example.com", "name": "New User"}
                    """))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.id").value(1));
    }

    @Test
    void createUser_returns400_withInvalidEmail() throws Exception {
        mockMvc.perform(post("/api/users")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"email": "invalid", "name": "User"}
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.errors[0]").value("Invalid email format"));
    }
}
```

### Repository Test with TestContainers

```java
@DataJpaTest
@Testcontainers
class UserRepositorySpec {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15");

    @Autowired
    private UserRepository userRepository;

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Test
    void findByEmail_returnsUser_whenExists() {
        userRepository.save(new User(null, "test@example.com"));

        Optional<User> result = userRepository.findByEmail("test@example.com");

        assertThat(result).isPresent();
    }
}
```

## Full Integration Test

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class UserIntegrationSpec {

    @Autowired
    private TestRestTemplate restTemplate;

    @Test
    void fullUserLifecycle() {
        // Create
        ResponseEntity<User> createResponse = restTemplate.postForEntity(
            "/api/users",
            new UserRequest("test@example.com", "Test"),
            User.class
        );
        assertThat(createResponse.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        Long userId = createResponse.getBody().getId();

        // Read
        ResponseEntity<User> getResponse = restTemplate.getForEntity(
            "/api/users/" + userId,
            User.class
        );
        assertThat(getResponse.getBody().getEmail()).isEqualTo("test@example.com");

        // Delete
        restTemplate.delete("/api/users/" + userId);

        ResponseEntity<User> afterDelete = restTemplate.getForEntity(
            "/api/users/" + userId,
            User.class
        );
        assertThat(afterDelete.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }
}
```

## Running Tests

```bash
# All tests
./mvnw test

# Specific test class
./mvnw test -Dtest=UserServiceSpec

# With Gradle
./gradlew test

# Specific test
./gradlew test --tests "UserServiceSpec"
```

## Test Directory Structure

```
src/
├── main/java/com/example/
│   ├── controller/
│   ├── service/
│   └── repository/
└── test/java/com/example/
    ├── controller/
    │   └── UserControllerSpec.java
    ├── service/
    │   └── UserServiceSpec.java
    └── repository/
        └── UserRepositorySpec.java
```
