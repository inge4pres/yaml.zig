const std = @import("std");
const testing = std.testing;
const yaml = @import("yaml");

// Tests with random YAML strings exercising various YAML features
// Each test parses a comprehensive YAML document and validates the parsed structure

test "text: deployment configuration" {
    const input =
        \\apiVersion: apps/v1
        \\kind: Deployment
        \\metadata:
        \\  name: nginx-deployment
        \\  replicas: 3
        \\  labels:
        \\    app: nginx
        \\    env: production
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    try testing.expectEqual(@as(usize, 3), root.count());
    try testing.expectEqualStrings("apps/v1", root.get("apiVersion").?.asString().?);
    try testing.expectEqualStrings("Deployment", root.get("kind").?.asString().?);

    var metadata = root.getPtr("metadata").?;
    const metadata_map = metadata.asMapping().?;
    try testing.expectEqual(@as(usize, 3), metadata_map.count());
    try testing.expectEqualStrings("nginx-deployment", metadata_map.get("name").?.asString().?);
    try testing.expectEqual(@as(i64, 3), metadata_map.get("replicas").?.asInt().?);

    var labels = metadata_map.getPtr("labels").?;
    const labels_map = labels.asMapping().?;
    try testing.expectEqual(@as(usize, 2), labels_map.count());
    try testing.expectEqualStrings("nginx", labels_map.get("app").?.asString().?);
    try testing.expectEqualStrings("production", labels_map.get("env").?.asString().?);
}

test "text: mixed flow and block styles" {
    const input =
        \\servers:
        \\  - {host: server1.example.com, port: 8080, active: true}
        \\  - {host: server2.example.com, port: 8081, active: false}
        \\databases:
        \\  primary:
        \\    host: db1.example.com
        \\    credentials: [admin, secret123]
        \\  replica:
        \\    host: db2.example.com
        \\    credentials: [readonly, pass456]
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;

    var servers = root.getPtr("servers").?;
    const servers_seq = servers.asSequence().?;
    try testing.expectEqual(@as(usize, 2), servers_seq.items.len);

    var server1 = &servers_seq.items[0];
    const server1_map = server1.asMapping().?;
    try testing.expectEqualStrings("server1.example.com", server1_map.get("host").?.asString().?);
    try testing.expectEqual(@as(i64, 8080), server1_map.get("port").?.asInt().?);
    try testing.expectEqual(true, server1_map.get("active").?.asBool().?);

    var databases = root.getPtr("databases").?;
    const databases_map = databases.asMapping().?;
    var primary = databases_map.getPtr("primary").?;
    const primary_map = primary.asMapping().?;

    var credentials = primary_map.getPtr("credentials").?;
    const credentials_seq = credentials.asSequence().?;
    try testing.expectEqual(@as(usize, 2), credentials_seq.items.len);
    try testing.expectEqualStrings("admin", credentials_seq.items[0].asString().?);
}

test "text: production environment configuration" {
    const input =
        \\environment:
        \\  production:
        \\    settings:
        \\      debug: false
        \\      host: prod.example.com
        \\      port: 443
        \\      timeout: 60
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    var environment = root.getPtr("environment").?;
    const env_map = environment.asMapping().?;

    var production = env_map.getPtr("production").?;
    const prod_map = production.asMapping().?;

    var settings = prod_map.getPtr("settings").?;
    const settings_map = settings.asMapping().?;

    try testing.expectEqual(@as(usize, 4), settings_map.count());
    try testing.expectEqual(@as(i64, 60), settings_map.get("timeout").?.asInt().?);
    try testing.expectEqualStrings("prod.example.com", settings_map.get("host").?.asString().?);
    try testing.expectEqual(false, settings_map.get("debug").?.asBool().?);
    try testing.expectEqual(@as(i64, 443), settings_map.get("port").?.asInt().?);
}

test "text: complex nested data with all scalar types" {
    const input =
        \\application:
        \\  config:
        \\    version: 2.1.0
        \\    build: 0x2A
        \\    permissions: 0o755
        \\    ratio: 3.14159
        \\    scientific: 6.022e23
        \\    enabled: true
        \\    disabled: false
        \\    empty: null
        \\    placeholder: ~
        \\    infinity: .inf
        \\    negative_infinity: -.inf
        \\    not_a_number: .nan
        \\    plain_string: Hello World
        \\    quoted_string: 'It''s working'
        \\    escaped_string: "Line 1\nLine 2"
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    var application = root.getPtr("application").?;
    const app_map = application.asMapping().?;

    var config = app_map.getPtr("config").?;
    const config_map = config.asMapping().?;

    // Test all scalar types in one mapping
    try testing.expectEqualStrings("2.1.0", config_map.get("version").?.asString().?);
    try testing.expectEqual(@as(i64, 0x2A), config_map.get("build").?.asInt().?);
    try testing.expectEqual(@as(i64, 0o755), config_map.get("permissions").?.asInt().?);
    try testing.expectEqual(@as(f64, 3.14159), config_map.get("ratio").?.asFloat().?);
    try testing.expectEqual(true, config_map.get("enabled").?.asBool().?);
    try testing.expectEqual(false, config_map.get("disabled").?.asBool().?);
    try testing.expect(config_map.get("empty").?.isNull());
    try testing.expect(config_map.get("placeholder").?.isNull());

    const inf = config_map.get("infinity").?.asFloat().?;
    try testing.expect(std.math.isInf(inf) and inf > 0);

    const neg_inf = config_map.get("negative_infinity").?.asFloat().?;
    try testing.expect(std.math.isInf(neg_inf) and neg_inf < 0);

    const nan = config_map.get("not_a_number").?.asFloat().?;
    try testing.expect(std.math.isNan(nan));

    try testing.expectEqualStrings("Hello World", config_map.get("plain_string").?.asString().?);
    try testing.expectEqualStrings("It's working", config_map.get("quoted_string").?.asString().?);
    try testing.expectEqualStrings("Line 1\nLine 2", config_map.get("escaped_string").?.asString().?);
}

test "text: deeply nested structure" {
    const input =
        \\level1:
        \\  level2:
        \\    level3:
        \\      level4:
        \\        level5:
        \\          data: deep value
        \\          numbers: [1, 2, 3, 4, 5]
        \\          nested_map:
        \\            key1: value1
        \\            key2: value2
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    var l1 = root.getPtr("level1").?;
    var l2 = l1.asMapping().?.getPtr("level2").?;
    var l3 = l2.asMapping().?.getPtr("level3").?;
    var l4 = l3.asMapping().?.getPtr("level4").?;
    var l5 = l4.asMapping().?.getPtr("level5").?;
    const l5_map = l5.asMapping().?;

    try testing.expectEqualStrings("deep value", l5_map.get("data").?.asString().?);

    var numbers = l5_map.getPtr("numbers").?;
    const numbers_seq = numbers.asSequence().?;
    try testing.expectEqual(@as(usize, 5), numbers_seq.items.len);
    try testing.expectEqual(@as(i64, 5), numbers_seq.items[4].asInt().?);
}

test "text: array of mixed types" {
    const input =
        \\mixed_array:
        \\  - 42
        \\  - 3.14
        \\  - true
        \\  - false
        \\  - null
        \\  - plain string
        \\  - 'quoted string'
        \\  - [nested, array]
        \\  - {nested: map, with: values}
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    var mixed = root.getPtr("mixed_array").?;
    const mixed_seq = mixed.asSequence().?;

    try testing.expectEqual(@as(usize, 9), mixed_seq.items.len);
    try testing.expectEqual(@as(i64, 42), mixed_seq.items[0].asInt().?);
    try testing.expectEqual(@as(f64, 3.14), mixed_seq.items[1].asFloat().?);
    try testing.expectEqual(true, mixed_seq.items[2].asBool().?);
    try testing.expectEqual(false, mixed_seq.items[3].asBool().?);
    try testing.expect(mixed_seq.items[4].isNull());
    try testing.expectEqualStrings("plain string", mixed_seq.items[5].asString().?);
    try testing.expectEqualStrings("quoted string", mixed_seq.items[6].asString().?);

    var nested_array = &mixed_seq.items[7];
    const nested_array_seq = nested_array.asSequence().?;
    try testing.expectEqual(@as(usize, 2), nested_array_seq.items.len);

    var nested_map = &mixed_seq.items[8];
    const nested_map_map = nested_map.asMapping().?;
    try testing.expectEqualStrings("map", nested_map_map.get("nested").?.asString().?);
}

test "text: multiline strings and comments" {
    const input =
        \\# This is a configuration file
        \\app_name: MyApp  # Application name
        \\description: |
        \\  This is a multi-line
        \\  description that preserves
        \\  line breaks.
        \\summary: >
        \\  This summary will be
        \\  folded into a single
        \\  line.
        \\# More comments
        \\version: 1.0.0
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    try testing.expectEqualStrings("MyApp", root.get("app_name").?.asString().?);

    const description = root.get("description").?.asString().?;
    try testing.expect(std.mem.indexOf(u8, description, "\n") != null);

    const summary = root.get("summary").?.asString().?;
    try testing.expect(std.mem.indexOf(u8, summary, "folded") != null);

    try testing.expectEqualStrings("1.0.0", root.get("version").?.asString().?);
}

test "text: ci/cd pipeline job configuration" {
    const input =
        \\pipeline:
        \\  build_job:
        \\    name: Build
        \\    runs-on: ubuntu-latest
        \\    steps:
        \\      - uses: actions/checkout@v2
        \\      - name: Setup
        \\        run: npm install
        \\      - name: Test
        \\        run: npm test
        \\      - name: Build
        \\        run: npm run build
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    var pipeline = root.getPtr("pipeline").?;
    const pipeline_map = pipeline.asMapping().?;

    var build_job = pipeline_map.getPtr("build_job").?;
    const build_map = build_job.asMapping().?;
    try testing.expectEqualStrings("Build", build_map.get("name").?.asString().?);
    try testing.expectEqualStrings("ubuntu-latest", build_map.get("runs-on").?.asString().?);

    var steps = build_map.getPtr("steps").?;
    const steps_seq = steps.asSequence().?;
    try testing.expectEqual(@as(usize, 4), steps_seq.items.len);

    var step1 = &steps_seq.items[0];
    const step1_map = step1.asMapping().?;
    try testing.expectEqualStrings("actions/checkout@v2", step1_map.get("uses").?.asString().?);

    var step2 = &steps_seq.items[1];
    const step2_map = step2.asMapping().?;
    try testing.expectEqualStrings("Setup", step2_map.get("name").?.asString().?);
    try testing.expectEqualStrings("npm install", step2_map.get("run").?.asString().?);
}

test "text: schema type detection" {
    const input =
        \\data:
        \\  is_string: hello
        \\  is_int: 456
        \\  is_float: 789.0
        \\  is_bool: true
        \\  is_null: null
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    var data = root.getPtr("data").?;
    const data_map = data.asMapping().?;

    // Verify automatic schema type detection
    try testing.expectEqualStrings("hello", data_map.get("is_string").?.asString().?);
    try testing.expectEqual(@as(i64, 456), data_map.get("is_int").?.asInt().?);
    try testing.expectEqual(@as(f64, 789.0), data_map.get("is_float").?.asFloat().?);
    try testing.expectEqual(true, data_map.get("is_bool").?.asBool().?);
    try testing.expect(data_map.get("is_null").?.isNull());
}

test "text: special values" {
    const input =
        \\test_data:
        \\  zero: 0
        \\  negative: -42
        \\  bool_true: true
        \\  bool_false: false
        \\  null_value: null
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    var test_data = root.getPtr("test_data").?;
    const data_map = test_data.asMapping().?;

    try testing.expectEqual(@as(i64, 0), data_map.get("zero").?.asInt().?);
    try testing.expectEqual(@as(i64, -42), data_map.get("negative").?.asInt().?);
    try testing.expectEqual(true, data_map.get("bool_true").?.asBool().?);
    try testing.expectEqual(false, data_map.get("bool_false").?.asBool().?);
    try testing.expect(data_map.get("null_value").?.isNull());
}

test "text: escape sequences" {
    const input =
        \\escaped_strings:
        \\  tab_escape: "Column1\tColumn2\tColumn3"
        \\  newline_escape: "Line1\nLine2\nLine3"
        \\  backslash: "Path\\to\\file"
        \\  quote: "He said \"hello\""
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    var escaped_strings = root.getPtr("escaped_strings").?;
    const strings_map = escaped_strings.asMapping().?;

    try testing.expectEqualStrings("Column1\tColumn2\tColumn3", strings_map.get("tab_escape").?.asString().?);
    try testing.expectEqualStrings("Line1\nLine2\nLine3", strings_map.get("newline_escape").?.asString().?);
    try testing.expectEqualStrings("Path\\to\\file", strings_map.get("backslash").?.asString().?);
    try testing.expectEqualStrings("He said \"hello\"", strings_map.get("quote").?.asString().?);
}

test "text: flow sequences and mappings deeply nested" {
    const input =
        \\test:
        \\  data: [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
        \\  matrix: [{x: 1, y: 2}, {x: 3, y: 4}]
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    var test_obj = root.getPtr("test").?;
    const test_map = test_obj.asMapping().?;

    var data = test_map.getPtr("data").?;
    const data_seq = data.asSequence().?;
    try testing.expectEqual(@as(usize, 3), data_seq.items.len);

    var first_row = &data_seq.items[0];
    const first_row_seq = first_row.asSequence().?;
    try testing.expectEqual(@as(usize, 3), first_row_seq.items.len);
    try testing.expectEqual(@as(i64, 1), first_row_seq.items[0].asInt().?);
    try testing.expectEqual(@as(i64, 2), first_row_seq.items[1].asInt().?);
    try testing.expectEqual(@as(i64, 3), first_row_seq.items[2].asInt().?);

    var matrix = test_map.getPtr("matrix").?;
    const matrix_seq = matrix.asSequence().?;
    try testing.expectEqual(@as(usize, 2), matrix_seq.items.len);

    var first_point = &matrix_seq.items[0];
    const first_point_map = first_point.asMapping().?;
    try testing.expectEqual(@as(i64, 1), first_point_map.get("x").?.asInt().?);
    try testing.expectEqual(@as(i64, 2), first_point_map.get("y").?.asInt().?);
}

test "text: comprehensive feature showcase" {
    const input =
        \\---
        \\# YAML feature showcase
        \\application:
        \\  name: MyApp
        \\  config:
        \\    database:
        \\      settings:
        \\        host: db.example.com
        \\        port: 5432
        \\        enabled: true
        \\        tags: [release, stable, v2]
    ;

    var parsed = try yaml.parseFromSlice(testing.allocator, input);
    defer parsed.deinit();

    const root = parsed.value.asMapping().?;
    var application = root.getPtr("application").?;
    const app_map = application.asMapping().?;

    // Validate basic fields
    try testing.expectEqualStrings("MyApp", app_map.get("name").?.asString().?);

    // Validate nested config
    var config = app_map.getPtr("config").?;
    const config_map = config.asMapping().?;
    var database = config_map.getPtr("database").?;
    const db_map = database.asMapping().?;

    var settings = db_map.getPtr("settings").?;
    const settings_map = settings.asMapping().?;

    try testing.expectEqualStrings("db.example.com", settings_map.get("host").?.asString().?);
    try testing.expectEqual(@as(i64, 5432), settings_map.get("port").?.asInt().?);
    try testing.expectEqual(true, settings_map.get("enabled").?.asBool().?);

    var tags = settings_map.getPtr("tags").?;
    const tags_seq = tags.asSequence().?;
    try testing.expectEqual(@as(usize, 3), tags_seq.items.len);
}
