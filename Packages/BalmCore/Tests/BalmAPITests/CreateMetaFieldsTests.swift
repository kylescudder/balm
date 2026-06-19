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
}
