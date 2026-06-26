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
}
