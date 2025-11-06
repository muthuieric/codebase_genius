walker mywalker {
    has name: str;
}

with entry:__main__ {
    print("It will be executed during jac run and will not be executed during jac serve");
}