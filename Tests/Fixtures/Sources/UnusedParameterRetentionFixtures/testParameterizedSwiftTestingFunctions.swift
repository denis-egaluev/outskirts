import Testing

struct ParameterizedTestHost {
    @Test(arguments: [1, 2])
    func parameterized(_ value: Int) {}

    @Test
    func entry() {
        helper(1)
    }

    func helper(_ value: Int) {}
}
