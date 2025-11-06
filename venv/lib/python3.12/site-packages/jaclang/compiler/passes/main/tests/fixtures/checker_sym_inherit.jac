
# -----------------------------------------------------------------------------
# Simple Inheritance
# -----------------------------------------------------------------------------

node Parent {
    has val: int = 42;
}

node Child (Parent) {

}


with entry {
    c = Child();
    c.val = 42;     # <-- Ok
    c.val = "str";  # <-- Error
}


# -----------------------------------------------------------------------------
# A Complex Inheritance
# -----------------------------------------------------------------------------

node Animal {
    has name: str;
}

node Cat(Animal) {
}

node Lion(Cat) {
}


with entry {
    l = Lion();

    l.name = "Simba";  # <-- Ok
    l.name = 42;       # <-- Error
}
