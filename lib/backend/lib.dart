import 'package:xml/xml.dart';

String prettyxml(dynamic object) {
  XmlElement element;
  
  if (object is XmlDocument) {
    element = object.rootElement;
  } else if (object is XmlElement) {
    element = object;
  } else {
    element = object as XmlElement;
  }
  
  return element.toXmlString(pretty: true, indent: "\t");
}
