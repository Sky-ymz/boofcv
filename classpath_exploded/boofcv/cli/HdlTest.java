/*
 * Test: directly instantiate HomographyDirectLinearTransform to see what's wrong
 */
package boofcv.cli;

import boofcv.alg.geo.h.HomographyDirectLinearTransform;
import boofcv.struct.geo.AssociatedPair;
import org.ejml.data.DMatrixRMaj;
import java.util.ArrayList;
import java.util.List;

/*
 * Test: directly instantiate HomographyDirectLinearTransform to see what's wrong
 */
package boofcv.cli;

import boofcv.alg.geo.h.HomographyDirectLinearTransform;

public class HdlTest {
	public static void main(String[] args) {
		HomographyDirectLinearTransform h = new HomographyDirectLinearTransform(false);
		System.out.println("done");
	}
}