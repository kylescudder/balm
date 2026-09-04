import XCTest
@testable import BalmAPI

final class CreateMetaFieldsTests: XCTestCase {
    private func decodeFields(_ json: String) throws -> [MetadataEndpoints.CreateMetaFields.FieldMeta] {
        try JSONDecoder().decode(
            MetadataEndpoints.CreateMetaFields.Response.self,
            from: Data(json.utf8)
        ).fields
    }

    func testResolvesCustomSelectComponentField() throws {
        // Team-managed tenant: "Component" is a custom select; options use `value`.
        let fields = try decodeFields(#"""
        {"fields":[
          {"fieldId":"summary","key":"summary","name":"Summary"},
          {"fieldId":"customfield_10312","key":"customfield_10312","name":"Component",
           "allowedValues":[
             {"value":"Odyssey Web Client","id":"10468"},
             {"value":"Saturn Mobile Client","id":"10428"}
           ]}
        ]}
        """#)
        let resolved = MetadataEndpoints.CreateMetaFields.resolveComponentField(from: fields)
        XCTAssertEqual(resolved?.jqlField, "cf[10312]")
        XCTAssertEqual(resolved?.values, ["Odyssey Web Client", "Saturn Mobile Client"])
    }

    func testPrefersStandardComponentsField() throws {
        let fields = try decodeFields(#"""
        {"fields":[
          {"fieldId":"components","key":"components","name":"Components",
           "allowedValues":[{"name":"API","id":"1"},{"name":"Web","id":"2"}]},
          {"fieldId":"customfield_10312","name":"Component",
           "allowedValues":[{"value":"Odyssey","id":"3"}]}
        ]}
        """#)
        let resolved = MetadataEndpoints.CreateMetaFields.resolveComponentField(from: fields)
        XCTAssertEqual(resolved?.jqlField, "component")
        XCTAssertEqual(resolved?.values, ["API", "Web"])
    }

    func testReturnsNilWhenNoComponentField() throws {
        let fields = try decodeFields(#"{"fields":[{"fieldId":"summary","name":"Summary"}]}"#)
        XCTAssertNil(MetadataEndpoints.CreateMetaFields.resolveComponentField(from: fields))
    }

    // MARK: - Create-form resolution (field id + arity + required + option ids)

    // The create modal needs the full field — id, arity, required, option ids —
    // not just the JQL labels. MP5's "Component" is a required single-select.
    func testComponentFieldResolvesCustomSingleSelectForCreate() throws {
        let fields = try decodeFields(#"""
        {"fields":[
          {"fieldId":"summary","name":"Summary","required":true},
          {"fieldId":"customfield_10312","name":"Component","required":true,
           "schema":{"type":"option","custom":"…:select","customId":10312},
           "allowedValues":[
             {"value":"Odyssey Web Client","id":"10468"},
             {"value":"Saturn Mobile Client","id":"10428"}
           ]}
        ]}
        """#)
        let field = MetadataEndpoints.CreateMetaFields.componentField(from: fields)
        XCTAssertEqual(field?.identifier, "customfield_10312")
        XCTAssertEqual(field?.required, true)
        XCTAssertFalse(field?.isMultiValue ?? true, "type 'option' is single-value")
        let options = (field?.allowedValues ?? []).compactMap { v -> (String, String)? in
            guard let id = v.id, let label = v.label else { return nil }
            return (id, label)
        }
        XCTAssertEqual(options.map(\.0), ["10468", "10428"])
        XCTAssertEqual(options.first?.1, "Odyssey Web Client")
    }

    // The standard `components` field is an array → multi-value.
    func testComponentFieldStandardIsMultiValue() throws {
        let fields = try decodeFields(#"""
        {"fields":[
          {"fieldId":"components","name":"Components","required":false,
           "schema":{"type":"array","items":"component","system":"components"},
           "allowedValues":[{"name":"API","id":"1"}]}
        ]}
        """#)
        let field = MetadataEndpoints.CreateMetaFields.componentField(from: fields)
        XCTAssertEqual(field?.identifier, "components")
        XCTAssertTrue(field?.isMultiValue ?? false, "type 'array' is multi-value")
        XCTAssertEqual(field?.allowedValues?.first?.id, "1")
        XCTAssertEqual(field?.allowedValues?.first?.label, "API")
    }

    // MARK: - Non-standard component field names

    /// MP5's "Internal Improvement" type requires `customfield_11906`, named
    /// "Internal Component". The old exact-name rule missed it, so the create
    /// form hid the picker and Jira rejected the create with
    /// "Internal Component: Internal Component is required."
    func testResolvesComponentFieldNamedInternalComponent() throws {
        let fields = try decodeFields(#"""
        {"fields":[
          {"fieldId":"summary","key":"summary","name":"Summary",
           "required":true,"schema":{"type":"string","system":"summary"}},
          {"fieldId":"customfield_11906","key":"customfield_11906","name":"Internal Component",
           "required":true,
           "schema":{"type":"option","custom":"com.atlassian.jira.plugin.system.customfieldtypes:select","customId":11906},
           "allowedValues":[
             {"value":"Bifrost","id":"14647"},
             {"value":"Odyssey","id":"14648"},
             {"value":"Jira","id":"14649"}
           ]}
        ]}
        """#)

        let field = MetadataEndpoints.CreateMetaFields.componentField(from: fields)

        XCTAssertEqual(field?.identifier, "customfield_11906")
        XCTAssertEqual(field?.name, "Internal Component")
        XCTAssertEqual(field?.required, true)
        XCTAssertFalse(field?.isMultiValue ?? true)

        let resolved = MetadataEndpoints.CreateMetaFields.resolveComponentField(from: fields)
        XCTAssertEqual(resolved?.jqlField, "cf[11906]")
        XCTAssertEqual(resolved?.values, ["Bifrost", "Odyssey", "Jira"])
    }

    /// A plainly named "Component" outranks a qualified one, so the filter path
    /// keeps resolving cf[10312] for the types that carry it.
    func testPrefersTheExactlyNamedComponentFieldOverAQualifiedOne() throws {
        let fields = try decodeFields(#"""
        {"fields":[
          {"fieldId":"customfield_11906","key":"customfield_11906","name":"Internal Component",
           "required":true,"schema":{"type":"option"},
           "allowedValues":[{"value":"Bifrost","id":"14647"}]},
          {"fieldId":"customfield_10312","key":"customfield_10312","name":"Component",
           "required":true,"schema":{"type":"option"},
           "allowedValues":[{"value":"Odyssey Web Client","id":"10468"}]}
        ]}
        """#)

        XCTAssertEqual(
            MetadataEndpoints.CreateMetaFields.componentField(from: fields)?.identifier,
            "customfield_10312"
        )
    }

    /// The standard system field still wins outright.
    func testPrefersStandardComponentsOverAQualifiedCustomField() throws {
        let fields = try decodeFields(#"""
        {"fields":[
          {"fieldId":"customfield_11906","key":"customfield_11906","name":"Internal Component",
           "required":true,"schema":{"type":"option"},
           "allowedValues":[{"value":"Bifrost","id":"14647"}]},
          {"fieldId":"components","key":"components","name":"Components",
           "schema":{"type":"array","system":"components"},
           "allowedValues":[{"name":"API","id":"1"}]}
        ]}
        """#)

        XCTAssertEqual(
            MetadataEndpoints.CreateMetaFields.componentField(from: fields)?.identifier,
            "components"
        )
    }

    /// A required qualified field beats an optional one — the required field is
    /// the one that blocks the create.
    func testPrefersARequiredQualifiedFieldOverAnOptionalOne() throws {
        let fields = try decodeFields(#"""
        {"fields":[
          {"fieldId":"customfield_20001","key":"customfield_20001","name":"Optional Component",
           "required":false,"schema":{"type":"option"},
           "allowedValues":[{"value":"A","id":"1"}]},
          {"fieldId":"customfield_11906","key":"customfield_11906","name":"Required Component",
           "required":true,"schema":{"type":"option"},
           "allowedValues":[{"value":"Bifrost","id":"14647"}]}
        ]}
        """#)

        XCTAssertEqual(
            MetadataEndpoints.CreateMetaFields.componentField(from: fields)?.identifier,
            "customfield_11906"
        )
    }

    func testResolvesAMultiValueQualifiedComponentField() throws {
        let fields = try decodeFields(#"""
        {"fields":[
          {"fieldId":"customfield_11906","key":"customfield_11906","name":"Affected Components",
           "required":true,"schema":{"type":"array"},
           "allowedValues":[{"value":"Bifrost","id":"14647"}]}
        ]}
        """#)

        let field = MetadataEndpoints.CreateMetaFields.componentField(from: fields)
        XCTAssertEqual(field?.identifier, "customfield_11906")
        XCTAssertTrue(field?.isMultiValue ?? false)
    }

    // MARK: - The loose match must not overreach

    /// "component" appearing in the name of a free-text field is not a picker.
    func testIgnoresAFreeTextFieldNamedLikeAComponent() throws {
        let fields = try decodeFields(#"""
        {"fields":[
          {"fieldId":"customfield_30001","key":"customfield_30001","name":"Component notes",
           "required":true,"schema":{"type":"string"}}
        ]}
        """#)

        XCTAssertNil(MetadataEndpoints.CreateMetaFields.componentField(from: fields))
        XCTAssertNil(MetadataEndpoints.CreateMetaFields.resolveComponentField(from: fields))
    }

    func testIgnoresAUserFieldNamedLikeAComponent() throws {
        let fields = try decodeFields(#"""
        {"fields":[
          {"fieldId":"customfield_30002","key":"customfield_30002","name":"Component owner",
           "required":true,"schema":{"type":"user"}}
        ]}
        """#)

        XCTAssertNil(MetadataEndpoints.CreateMetaFields.componentField(from: fields))
    }

    func testIgnoresAnUnrelatedRequiredSelect() throws {
        let fields = try decodeFields(#"""
        {"fields":[
          {"fieldId":"customfield_10801","key":"customfield_10801","name":"Instance",
           "required":true,"schema":{"type":"option"},
           "allowedValues":[{"value":"eu-1","id":"1"}]}
        ]}
        """#)

        XCTAssertNil(MetadataEndpoints.CreateMetaFields.componentField(from: fields))
    }

    /// Selection must not depend on the order Jira returns the fields in.
    func testSelectionIsIndependentOfFieldOrder() throws {
        let json = #"""
        {"fields":[
          {"fieldId":"customfield_10312","key":"customfield_10312","name":"Component",
           "required":true,"schema":{"type":"option"},"allowedValues":[{"value":"A","id":"1"}]},
          {"fieldId":"customfield_11906","key":"customfield_11906","name":"Internal Component",
           "required":true,"schema":{"type":"option"},"allowedValues":[{"value":"B","id":"2"}]}
        ]}
        """#
        let reversed = #"""
        {"fields":[
          {"fieldId":"customfield_11906","key":"customfield_11906","name":"Internal Component",
           "required":true,"schema":{"type":"option"},"allowedValues":[{"value":"B","id":"2"}]},
          {"fieldId":"customfield_10312","key":"customfield_10312","name":"Component",
           "required":true,"schema":{"type":"option"},"allowedValues":[{"value":"A","id":"1"}]}
        ]}
        """#

        XCTAssertEqual(
            MetadataEndpoints.CreateMetaFields.componentField(from: try decodeFields(json))?.identifier,
            MetadataEndpoints.CreateMetaFields.componentField(from: try decodeFields(reversed))?.identifier
        )
    }
}
