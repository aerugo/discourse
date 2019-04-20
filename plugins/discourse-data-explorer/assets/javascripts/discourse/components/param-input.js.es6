// import Category from 'discourse/models/category';
const Category = Discourse.Category;

const layoutMap = {
  int: "int",
  bigint: "int",
  boolean: "boolean",
  string: "generic",
  time: "generic",
  date: "generic",
  datetime: "generic",
  double: "string",
  user_id: "user_id",
  post_id: "string",
  topic_id: "generic",
  category_id: "generic",
  group_id: "generic",
  badge_id: "generic",
  int_list: "generic",
  string_list: "generic",
  user_list: "user_list"
};

function allowsInputTypeTime() {
  try {
    const inp = document.createElement("input");
    inp.attributes.type = "time";
    inp.attributes.type = "date";
    return true;
  } catch (e) {
    return false;
  }
}

export default Ember.Component.extend({
  classNameBindings: ["valid:valid:invalid", ":param"],

  boolTypes: [
    { name: I18n.t("explorer.types.bool.true"), id: "Y" },
    { name: I18n.t("explorer.types.bool.false"), id: "N" },
    { name: I18n.t("explorer.types.bool.null_"), id: "#null" }
  ],

  value: Ember.computed("params", "info.identifier", {
    get() {
      return this.get("params")[this.get("info.identifier")];
    },
    set(key, value) {
      this.get("params")[this.get("info.identifier")] = value.toString();
      return value;
    }
  }),

  valueBool: Ember.computed("params", "info.identifier", {
    get() {
      return this.get("params")[this.get("info.identifier")] !== "false";
    },
    set(key, value) {
      value = !!value;
      this.get("params")[this.get("info.identifier")] = value.toString();
      return value;
    }
  }),

  valid: function() {
    const type = this.get("info.type"),
      value = this.get("value");

    if (Ember.isEmpty(this.get("value"))) {
      return this.get("info.nullable");
    }

    const intVal = parseInt(value, 10);
    const intValid =
      !isNaN(intVal) && intVal < 2147483648 && intVal > -2147483649;
    const isPositiveInt = /^\d+$/.test(value);
    switch (type) {
      case "int":
        return /^-?\d+$/.test(value) && intValid;
      case "bigint":
        return /^-?\d+$/.test(value) && !isNaN(intVal);
      case "boolean":
        return /^Y|N|#null|true|false/.test(value);
      case "double":
        return (
          !isNaN(parseFloat(value)) ||
          /^(-?)Inf(inity)?$/i.test(value) ||
          /^(-?)NaN$/i.test(value)
        );
      case "int_list":
        return value.split(",").every(function(i) {
          return /^(-?\d+|null)$/.test(i.trim());
        });
      case "post_id":
        return isPositiveInt || /\d+\/\d+(\?u=.*)?$/.test(value);
      case "category_id":
        if (!isPositiveInt && value !== value.dasherize()) {
          this.set("value", value.dasherize());
        }

        if (isPositiveInt) {
          return !!this.site.categories.find(function(c) {
            return c.get("id") === intVal;
          });
        } else if (/\//.test(value)) {
          const match = /(.*)\/(.*)/.exec(value);
          if (!match) return false;
          const result = Category.findBySlug(
            match[2].dasherize(),
            match[1].dasherize()
          );
          return !!result;
        } else {
          return !!Category.findBySlug(value.dasherize());
        }
      case "group_id":
        const groups = this.site.get("groups");
        if (isPositiveInt) {
          return !!groups.find(function(g) {
            return g.id === intVal;
          });
        } else {
          return !!groups.find(function(g) {
            return g.name === value;
          });
        }
    }
    return true;
  }.property("value", "info.type", "info.nullable"),

  layoutType: function() {
    const type = this.get("info.type");
    if ((type === "time" || type === "date") && !allowsInputTypeTime()) {
      return "string";
    }
    if (layoutMap[type]) {
      return layoutMap[type];
    }
    return "generic";
  }.property("info.type"),

  layoutName: function() {
    return "admin/components/q-params/" + this.get("layoutType");
  }.property("layoutType")
});
